//
// App.swift — Milestone 1 : app menu bar (LSUIElement), SwiftUI MenuBarExtra.
// Pas de @main ici : main.swift décide entre self-test CLI et lancement GUI.
//
// Milestone 2 : l'overlay (NotchOverlayController) est retenu par un `let` simple, pas un
// @StateObject — c'est un contrôleur AppKit sans état SwiftUI à observer, il doit juste survivre
// aussi longtemps que l'app.

import SwiftUI
import BouncerCore
import Sentry

struct BouncerApp: App {
    @StateObject private var windowManager: WindowManager
    /// UNE instance de réglages pour toute l'app, créée ici et passée à la main. Deux instances
    /// liraient les mêmes clés mais ne se préviendraient pas : bouger un curseur dans la fenêtre
    /// de réglages ne changerait rien à l'overlay tant que l'app ne serait pas relancée.
    @StateObject private var reglages: Reglages
    private let overlayController: NotchOverlayController
    private let accueilController: FenetreAccueilController
    /// Un `let` comme l'overlay, et surtout PAS un `@StateObject` — MESURÉ le 2026-09-05 sur le
    /// bundle installé : la valeur d'un `@StateObject` n'est construite que lorsque la scène qui
    /// le lit est évaluée pour la première fois. Celui-ci n'est lu que par la scène `Settings`,
    /// donc le raccourci global ne s'enregistrait qu'à la première ouverture des réglages, et
    /// ⌃⌥⌘B ne faisait rien avant. Le contrôleur reste observable : c'est `VueReglages` qui le
    /// prend en `@ObservedObject`, et sa durée de vie est celle de l'app.
    private let raccourci: RaccourciGlobalController
    /// Démarre Sentry quand l'utilisateur coche « Envoyer les rapports de plantage », l'arrête
    /// quand il décoche. Par défaut rien ne démarre. Un `let` pour la même raison que `raccourci` :
    /// il doit vivre dès le lancement, pas à la première évaluation d'une scène.
    private let rapportsPlantage: PiloteRapportsPlantage

    init() {
        let reglages = Reglages()
        _reglages = StateObject(wrappedValue: reglages)
        rapportsPlantage = PiloteRapportsPlantage(reglages: reglages, demarrer: Self.demarrerSentry,
                                                  arreter: { SentrySDK.close() })
        let windowManager = WindowManager(reglages: reglages)
        _windowManager = StateObject(wrappedValue: windowManager)
        overlayController = NotchOverlayController(windowManager: windowManager, reglages: reglages)

        // Le raccourci aboutit exactement là où aboutissent le swipe et les flèches — `cycle` est
        // le point d'entrée unique, et un quatrième chemin vers la bascule serait un quatrième
        // comportement à garder synchrone. Sens avant, comme le swipe : les flèches sont le seul
        // geste qui remonte le cycle, parce qu'elles sont les seules à pouvoir le montrer.
        raccourci = RaccourciGlobalController(reglages: reglages) {
            windowManager.cycle(forward: true)
        }

        // L'accueil s'affiche APRÈS le retour de cet init : ordonner une fenêtre à l'écran depuis
        // l'init d'un `App` la pose avant que l'app ait fini son lancement, et elle n'obtient
        // alors pas le focus. Un tour de run loop suffit.
        let accueil = FenetreAccueilController(windowManager: windowManager)
        accueilController = accueil
        DispatchQueue.main.async {
            MainActor.assumeIsolated { accueil.afficherSiPremierLancement() }
        }
    }

    /// Error monitoring seul : pas de tracing, pas de profiling, pas de suivi de sessions.
    private static func demarrerSentry() {
        SentrySDK.start { options in
            options.dsn = "https://df3cae4a19aed384f3763d1e27ab0e12@o4511827012419584.ingest.de.sentry.io/4512097601847376"
            options.debug = false
            // Pas d'IP, pas de device context nominatif dans les events.
            options.sendDefaultPii = false
            // Le suivi de sessions enverrait un ping à chaque lancement, plantage ou non : ce
            // n'est pas ce que l'utilisateur a accepté en cochant « rapports de plantage ».
            options.enableAutoSessionTracking = false
            options.environment = "production"
            options.releaseName = "bouncer@\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")"
        }
    }

    var body: some Scene {
        // L'icône change quand la dernière bascule a échoué : un swipe raté ne bouge rien à
        // l'écran, et le message qui l'explique dort dans un menu que personne n'ouvrira sans
        // raison de le faire.
        //
        // Et elle change AUSSI pendant la bascule, parce que c'est là que N3 faisait mal : une app
        // qui traîne à quitter fait patienter le geste, `basculer` refuse tout second geste, et
        // jusqu'ici rien à l'écran ne le disait. Le `◐` du menu ne compte pas — personne n'a le
        // menu ouvert en swipant. La barre des menus, elle, est toujours visible : c'est la seule
        // surface qui répond au geste sans qu'on ait rien à ouvrir.
        //
        // L'Accessibilité absente allume aussi le triangle : sans elle Bouncer ne fait rien, et
        // une icône normale laissait croire qu'il tournait. C'est le premier lancement typique.
        MenuBarExtra(
            "Bouncer",
            systemImage: windowManager.bundleIDEnCoursDeBascule != nil
                ? "hourglass"
                : (windowManager.echecBascule == nil && windowManager.accessibilityTrusted
                    ? "rectangle.on.rectangle" : "exclamationmark.triangle")
        ) {
            MenuBarContentView(
                windowManager: windowManager,
                reglages: reglages,
                ouvrirAccueil: { [accueilController] in accueilController.afficher() }
            )
        }

        // Scène `Settings` : macOS lui donne le titre localisé, ⌘, et la position mémorisée. Cf.
        // FenetreReglages.swift.
        Settings {
            VueReglages(windowManager: windowManager, reglages: reglages, raccourci: raccourci)
        }
    }
}
