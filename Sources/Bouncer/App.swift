//
// App.swift — Milestone 1 : app menu bar (LSUIElement), SwiftUI MenuBarExtra.
// Pas de @main ici : main.swift décide entre self-test CLI et lancement GUI.
//
// Milestone 2 : l'overlay (NotchOverlayController) est retenu par un `let` simple, pas un
// @StateObject — c'est un contrôleur AppKit sans état SwiftUI à observer, il doit juste survivre
// aussi longtemps que l'app.

import SwiftUI
import BouncerCore

struct BouncerApp: App {
    @StateObject private var windowManager: WindowManager
    /// UNE instance de réglages pour toute l'app, créée ici et passée à la main. Deux instances
    /// liraient les mêmes clés mais ne se préviendraient pas : bouger un curseur dans la fenêtre
    /// de réglages ne changerait rien à l'overlay tant que l'app ne serait pas relancée.
    @StateObject private var reglages: Reglages
    private let overlayController: NotchOverlayController
    private let accueilController: FenetreAccueilController

    init() {
        let reglages = Reglages()
        _reglages = StateObject(wrappedValue: reglages)
        let windowManager = WindowManager(reglages: reglages)
        _windowManager = StateObject(wrappedValue: windowManager)
        overlayController = NotchOverlayController(windowManager: windowManager, reglages: reglages)

        // L'accueil s'affiche APRÈS le retour de cet init : ordonner une fenêtre à l'écran depuis
        // l'init d'un `App` la pose avant que l'app ait fini son lancement, et elle n'obtient
        // alors pas le focus. Un tour de run loop suffit.
        let accueil = FenetreAccueilController(windowManager: windowManager)
        accueilController = accueil
        DispatchQueue.main.async {
            MainActor.assumeIsolated { accueil.afficherSiPremierLancement() }
        }
    }

    var body: some Scene {
        // L'icône change quand la dernière bascule a échoué : un swipe raté ne bouge rien à
        // l'écran, et le message qui l'explique dort dans un menu que personne n'ouvrira sans
        // raison de le faire.
        MenuBarExtra(
            "Bouncer",
            systemImage: windowManager.echecBascule == nil
                ? "rectangle.on.rectangle" : "exclamationmark.triangle"
        ) {
            MenuBarContentView(
                windowManager: windowManager,
                ouvrirAccueil: { [accueilController] in accueilController.afficher() }
            )
        }

        // Scène `Settings` : macOS lui donne le titre localisé, ⌘, et la position mémorisée. Cf.
        // FenetreReglages.swift.
        Settings {
            VueReglages(windowManager: windowManager, reglages: reglages)
        }
    }
}
