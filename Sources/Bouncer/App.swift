//
// App.swift — Milestone 1 : app menu bar (LSUIElement), SwiftUI MenuBarExtra.
// Pas de @main ici : main.swift décide entre self-test CLI et lancement GUI.
//
// Milestone 2 : l'overlay (NotchOverlayController) est retenu par un `let` simple, pas un
// @StateObject — c'est un contrôleur AppKit sans état SwiftUI à observer, il doit juste survivre
// aussi longtemps que l'app.

import SwiftUI

struct BouncerApp: App {
    @StateObject private var windowManager: WindowManager
    private let overlayController: NotchOverlayController

    init() {
        let windowManager = WindowManager()
        _windowManager = StateObject(wrappedValue: windowManager)
        overlayController = NotchOverlayController(windowManager: windowManager)
    }

    var body: some Scene {
        MenuBarExtra("Bouncer", systemImage: "rectangle.on.rectangle") {
            MenuBarContentView(windowManager: windowManager)
        }
    }
}
