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
                    windowManager.toggle(pid: app.pid)
                } label: {
                    Text("\(app.isHiddenByUs ? "○" : "●") \(app.name) — \(app.support.rawValue)")
                }
                .disabled(app.support != .supported)
            }
        }

        Divider()
        Button("Rafraîchir") { windowManager.refresh() }
        Button("Quitter") { NSApplication.shared.terminate(nil) }
    }
}
