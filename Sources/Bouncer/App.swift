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
    private let overlayController: NotchOverlayController

    init() {
        let windowManager = WindowManager()
        _windowManager = StateObject(wrappedValue: windowManager)
        overlayController = NotchOverlayController(windowManager: windowManager)
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
            MenuBarContentView(windowManager: windowManager)
        }
    }
}
