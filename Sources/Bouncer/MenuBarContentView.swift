import SwiftUI
import BouncerCore

struct MenuBarContentView: View {
    @ObservedObject var windowManager: WindowManager

    /// Rouvre la fenêtre de bienvenue. Le geste du produit — survoler l'encoche, swiper — ne
    /// s'écrit que là ; sans cette entrée, il devient introuvable dès l'accueil refermé.
    let ouvrirAccueil: () -> Void

    var body: some View {
        if !windowManager.accessibilityTrusted {
            Button("⚠️ Autoriser dans les Réglages…") {
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
            Text("Aucune app d'encoche détectée")
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
        Button("Guide de démarrage…") { ouvrirAccueil() }
        Button("Rafraîchir") { windowManager.refresh() }
        Button("Quitter") { NSApplication.shared.terminate(nil) }
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
        case .active: return "occupe l'encoche"
        case .inactive: return "n'occupe pas l'encoche"
        case .enCours: return "bascule en cours"
        }
    }
}
