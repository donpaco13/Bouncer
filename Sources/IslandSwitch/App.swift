//
// App.swift — Milestone 1 : app menu bar (LSUIElement), SwiftUI MenuBarExtra.
// Pas de @main ici : main.swift décide entre self-test CLI et lancement GUI.

import SwiftUI

struct IslandSwitchApp: App {
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        MenuBarExtra("Island Switch", systemImage: "rectangle.on.rectangle") {
            MenuBarContentView(windowManager: windowManager)
        }
    }
}
