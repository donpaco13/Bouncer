import SwiftUI
import BouncerCore

struct MenuBarContentView: View {
    @ObservedObject var windowManager: WindowManager

    var body: some View {
        if !windowManager.accessibilityTrusted {
            Button("⚠️ Autoriser dans les Réglages…") {
                windowManager.openAccessibilitySettings()
            }
            Divider()
        }

        if windowManager.apps.isEmpty {
            Text("Aucune app d'encoche détectée")
        } else {
            ForEach(windowManager.apps) { app in
                Button {
                    windowManager.toggle(bundleID: app.id)
                } label: {
                    Text("\(app.isHiddenByUs ? "○" : "●") \(app.name) — \(app.support.rawValue)")
                }
                // Une app arrêtée n'est pas masquable : la Task 5 la rendra cliquable, en la
                // relançant au lieu de la masquer.
                .disabled(app.support != .supported || !app.estLancee)
            }
        }

        Divider()
        Button("Rafraîchir") { windowManager.refresh() }
        Button("Quitter") { NSApplication.shared.terminate(nil) }
    }
}
