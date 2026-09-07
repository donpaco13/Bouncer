//
// Relance.swift — relance propre de Bouncer depuis elle-même.
//
// Relancer un agent d'arrière-plan macOS (LSUIElement = true) depuis son propre processus impose
// une contrainte absolue : la NOUVELLE instance doit démarrer STRICTEMENT APRÈS la mort de l'ancienne,
// jamais pendant.
//
// POURQUOI L'ENCHAÎNEMENT STRICT APRÈS MORT EST OBLIGATOIRE :
//   1. Deux instances simultanées créent deux fenêtres NSPanel d'overlay sur la même encoche.
//   2. Deux icônes MenuBarExtra apparaissent brièvement dans la barre des menus.
//   3. Lors de la terminaison, l'ancienne instance appelle `restaurerAppsMasquees()` dans son
//      handler `willTerminateNotification`. Si la nouvelle instance avait déjà démarré et pris la
//      main sur les apps d'encoche, ce nettoyage annulerait son travail.
//   4. Si Bouncer tourne en double, le scan de fenêtres pourrait s'auto-détecter si l'exclusion
//      échouait.
//
// COMPARAISON DES PATRONS :
//
// Patron A : `NSWorkspace.openApplication` sur son propre bundle puis `NSApp.terminate`
//   Écarté pour trois raisons majeures :
//   - Pour lancer une nouvelle instance d'une app déjà en cours, `openApplication` exige
//     `createsNewApplicationInstance = true`. Sans cela, il ne fait qu'activer l'instance existante
//     qui s'apprête à mourir (donc l'app quitte sans jamais redémarrer).
//   - Avec `createsNewApplicationInstance = true`, LaunchServices crée la seconde instance
//     IMMÉDIATEMENT : les deux instances coexistent pendant toute la durée de terminaison de
//     la première (démontage des fenêtres, notification willTerminate, libération des run loops),
//     soit 100 à 300 ms de double présence visible.
//   - `openApplication` étant asynchrone, appeler `NSApp.terminate` avant la fin du handshake
//     peut avorter le lancement ; et attendre le callback de complétion garantit que la 2e
//     instance a déjà commencé à tourner avant que la 1ère ne commence à mourir.
//
// Patron B : Processus helper détaché via `Process` (`while kill -0 $PID; do sleep 0.05; done; open "$APP"`)
//   Retenu car :
//   - Sérialisation stricte : la commande boucle tant que le PID de l'ancienne instance répond à
//     `kill -0`. La commande `open` n'est invoquée qu'APRÈS la disparition complète du process.
//   - Zéro coexistence : l'ancienne instance s'éteint proprement (overlay fermé, notification de
//     terminaison passée, ressources libérées), puis la nouvelle démarre dans un système propre.
//   - Utilisation de LaunchServices (`/usr/bin/open`) : `open` enregistre l'app auprès de
//     LaunchServices dans la session utilisateur courante, exactement comme un lancement Finder.
//   - Préservation de l'autorisation d'Accessibilité (TCC) : TCC associe l'autorisation au
//     Bundle Identifier (`io.github.donpaco13.bouncer`) et à sa Designated Requirement (signature
//     de code stable). Le lancement par `open` du même bundle conserve donc instantanément
//     `AXIsProcessTrusted() == true` sans demander de nouvelle confirmation.
//

import AppKit
import Foundation

/// Orchestre la relance de Bouncer en garantissant la non-coexistence des instances.
@MainActor
public final class RelanceurApp {
    public typealias ExecuteProcessus = (URL, [String]) throws -> Void
    public typealias TerminerApp = @MainActor () -> Void

    private let obtenirPID: () -> pid_t
    private let obtenirBundleURL: () -> URL
    private let executeProcessus: ExecuteProcessus
    private let terminerApp: TerminerApp

    public init(
        obtenirPID: @escaping () -> pid_t = { ProcessInfo.processInfo.processIdentifier },
        obtenirBundleURL: @escaping () -> URL = { Bundle.main.bundleURL },
        executeProcessus: @escaping ExecuteProcessus = { executable, arguments in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            try process.run()
        },
        terminerApp: @escaping TerminerApp = { @MainActor in
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.obtenirPID = obtenirPID
        self.obtenirBundleURL = obtenirBundleURL
        self.executeProcessus = executeProcessus
        self.terminerApp = terminerApp
    }

    public static let partage = RelanceurApp()

    /// Prépare la commande de relance détachée.
    ///
    /// Utilise des chemins absolus (`/bin/kill`, `/bin/sleep`, `/usr/bin/open`) pour ne pas
    /// dépendre de la variable d'environnement `PATH`.
    public static func commandeRelance(pid: pid_t, bundleURL: URL) -> (executable: URL, arguments: [String]) {
        let script: String
        if bundleURL.pathExtension == "app" {
            script = "while /bin/kill -0 $1 2>/dev/null; do /bin/sleep 0.05; done; /usr/bin/open \"$2\""
        } else {
            script = "while /bin/kill -0 $1 2>/dev/null; do /bin/sleep 0.05; done; \"$2\""
        }
        return (
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, "_", String(pid), bundleURL.path]
        )
    }

    /// Lance le helper détaché et quitte l'instance courante.
    ///
    /// Retourne `false` si le helper n'a pas pu être démarré (dans ce cas, l'app ne quitte pas,
    /// évitant de laisser l'utilisateur sans Bouncer).
    @discardableResult
    public func relancer() -> Bool {
        let pid = obtenirPID()
        let url = obtenirBundleURL()
        let commande = Self.commandeRelance(pid: pid, bundleURL: url)
        do {
            try executeProcessus(commande.executable, commande.arguments)
            terminerApp()
            return true
        } catch {
            return false
        }
    }
}
