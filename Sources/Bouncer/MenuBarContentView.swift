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

        let entrees = windowManager.entreesMenu
        if entrees.isEmpty {
            Text("Aucune app d'encoche détectée")
        } else {
            ForEach(entrees) { entree in
                Button {
                    windowManager.rendreActive(bundleID: entree.bundleID)
                } label: {
                    // Le libellé ne dit que le nom : c'est l'état, porté par le symbole, qui
                    // intéresse l'utilisateur. Le verdict de régissabilité passe en infobulle.
                    Label(entree.nom, systemImage: symbole(entree.etat))
                }
                .help(entree.detail)
                // Le symbole seul ne se lit pas au VoiceOver : l'état est redit en toutes lettres.
                .accessibilityLabel("\(entree.nom), \(descriptionEtat(entree.etat)). \(entree.detail)")
                // Aucun `.disabled` ici, volontairement. Une app résistante ou arrêtée est
                // cliquable comme les autres : c'est tout l'objet du chantier de bascule.
            }
        }

        Divider()
        Button("Rafraîchir") { windowManager.refresh() }
        Button("Quitter") { NSApplication.shared.terminate(nil) }
    }

    /// Un symbole sur chaque entrée, y compris inactive : c'est ce qui garde les libellés alignés
    /// et fait ressortir la marque de l'app active au lieu de la noyer.
    private func symbole(_ etat: EntreeMenu.Etat) -> String {
        switch etat {
        case .active: return "checkmark.circle.fill"
        case .inactive: return "circle"
        case .enCours: return "hourglass"
        }
    }

    private func descriptionEtat(_ etat: EntreeMenu.Etat) -> String {
        switch etat {
        case .active: return "occupe l'encoche"
        case .inactive: return "n'occupe pas l'encoche"
        case .enCours: return "bascule en cours"
        }
    }
}
