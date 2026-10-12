import AppKit
import SwiftUI
import BouncerCore

struct MenuBarContentView: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var reglages: Reglages

    /// Rouvre la fenêtre de bienvenue. Le geste du produit — survoler l'encoche, swiper — ne
    /// s'écrit que là ; sans cette entrée, il devient introuvable dès l'accueil refermé.
    let ouvrirAccueil: () -> Void

    var body: some View {
        if !windowManager.accessibilityTrusted {
            Button(texte("menu.grantAccess")) {
                windowManager.openAccessibilitySettings()
            }
            Divider()
        }

        if let echec = windowManager.echecBascule {
            // Une bascule ratée ne change rien à l'écran — c'est la garantie de la machine à
            // états, l'app précédente reste en place. Sans cette ligne, le geste passerait donc
            // pour non détecté. Rien à cliquer : il n'y a qu'à réessayer.
            Text("⚠️ \(echec)")
            Divider()
        }

        let entrees = windowManager.entreesMenu
        if entrees.isEmpty {
            Text(texte("menu.noNotchApp"))
        } else {
            ForEach(entrees) { entree in
                Button {
                    windowManager.rendreActive(bundleID: entree.bundleID)
                } label: {
                    // Le marqueur d'état est un CARACTÈRE, pas un SF Symbol : un menu de barre
                    // d'état macOS ne rend pas de façon fiable l'image d'un `Label`, et le
                    // symbole disparaissait purement et simplement à l'écran. Constaté en réel.
                    // Le verdict de régissabilité, lui, reste en infobulle.
                    Text("\(symbole(entree.etat))  \(entree.nom)")
                }
                .help(entree.detail)
                // Le symbole seul ne se lit pas au VoiceOver : l'état est redit en toutes lettres.
                .accessibilityLabel("\(entree.nom), \(descriptionEtat(entree.etat)). \(entree.detail)")
                // Aucun `.disabled` ici, volontairement. Une app résistante ou arrêtée est
                // cliquable comme les autres : c'est tout l'objet du chantier de bascule.
            }
        }

        Divider()
        Button(texte("menu.settings")) { Self.ouvrirReglages() }
            .keyboardShortcut(",", modifiers: .command)
        Button(texte("menu.welcomeGuide")) { ouvrirAccueil() }
        // Opt-in : décoché tant que l'utilisateur n'a rien fait. L'infobulle dit ce qui part et
        // ce qui ne part pas ; un menu n'a pas la place pour un paragraphe.
        Toggle(texte("menu.crashReports"), isOn: $reglages.rapportsPlantage)
            .help(texte("menu.crashReports.detail"))
            .accessibilityHint(texte("menu.crashReports.detail"))
        Button(texte("menu.refresh")) { windowManager.refresh() }
        Button(texte("menu.quit")) { NSApplication.shared.terminate(nil) }
    }

    /// Ouvre la scène `Settings`.
    ///
    /// Trois voies plus courtes ont été essayées et MESURÉES ici, toutes inutilisables :
    ///   - `SettingsLink` (la voie officielle macOS 14) : l'entrée est présente au tout premier
    ///     lancement puis DISPARAÎT du menu aux suivants — relevé deux fois sur l'arbre
    ///     d'accessibilité, le menu ne contenait plus que les apps, le séparateur, Guide,
    ///     Rafraîchir, Quitter ;
    ///   - `NSApp.sendAction(showSettingsWindow:, to: nil, …)` : rien ne s'ouvre. Une app
    ///     accessoire (`LSUIElement`) n'a pas de fenêtre clé, donc pas de chaîne de répondeurs à
    ///     remonter ;
    ///   - chercher ce même sélecteur dans le menu de l'app : il n'y est pas. Relevé sur le menu
    ///     réel, l'entrée « Réglages… » que SwiftUI installe porte `menuAction:`, son sélecteur
    ///     interne, et non `showSettingsWindow:`.
    ///
    /// Ce qui marche, vérifié : déclencher cette entrée-là. On l'identifie par son RACCOURCI ⌘,
    /// — jamais par son titre, localisé (« Settings… » en anglais), ni par son sélecteur, qui
    /// appartient à SwiftUI et peut changer sans préavis. Le raccourci, lui, est le contrat que
    /// macOS tient avec l'utilisateur : s'il bougeait, l'entrée ne serait plus celle qu'on veut.
    private static func ouvrirReglages() {
        // Un tour de run loop : le NSMenu est encore en cours de fermeture, et `activate` n'a pas
        // encore pris effet.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            guard let menuApp = NSApp.mainMenu?.items.first?.submenu,
                  let entree = menuApp.items.first(where: {
                      $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command
                  }),
                  let action = entree.action
            else { return }
            // `to: entree.target` et non `to: nil` : l'entrée de menu connaît son destinataire,
            // la chaîne des répondeurs non — c'est toute la différence avec la voie qui échouait.
            NSApp.sendAction(action, to: entree.target, from: entree)
        }
    }

    /// Un symbole sur chaque entrée, y compris inactive : c'est ce qui garde les libellés alignés
    /// et fait ressortir la marque de l'app active au lieu de la noyer.
    private func symbole(_ etat: EntreeMenu.Etat) -> String {
        switch etat {
        case .active: return "●"
        case .inactive: return "○"
        case .enCours: return "◐"
        }
    }

    private func descriptionEtat(_ etat: EntreeMenu.Etat) -> String {
        switch etat {
        case .active: return texte("menu.state.onStage")
        case .inactive: return texte("menu.state.waiting")
        case .enCours: return texte("menu.state.switching")
        }
    }
}
