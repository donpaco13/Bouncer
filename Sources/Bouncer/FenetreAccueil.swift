//
// FenetreAccueil.swift — Guide de démarrage de Bouncer.
//
// Le rôle de cette fenêtre : Bouncer est un utilitaire d'arrière-plan sans icône dans le Dock
// (`LSUIElement = true`). Au premier lancement, un utilisateur ne voit aucun repère familier.
// Ce guide explique et montre immédiatement trois choses indispensables :
//   1. Où vit l'app : dans la barre des menus en haut à droite, pas dans le Dock.
//   2. L'autorisation : l'Accessibilité système macOS, avec mise à jour réactive en direct.
//   3. Le geste central : survoler l'encoche, swiper à deux doigts.
//      Dynamique clé : un swipe horizontal avance d'une app quel que soit son sens (gauche ou droite),
//      et répéter le geste du même côté fait tourner toutes les apps en boucle continue (cycle infini).
//      Il n'y a aucun sens à retenir.
//
// Contraintes architecturales :
//   - NSWindow classique (pas de NSPanel non-activating) pour accepter le focus et les clics.
//   - NSHostingController avec .preferredContentSize : la fenêtre adapte sa hauteur au contenu.
//     Aucun ScrollView à la racine : un VStack direct garantit une mesure intrinsèque exacte.
//   - Aucun appel d'API AX direct : on lit uniquement l'état publié par WindowManager / EtatAccueil.
//   - Réactivité native : détection automatique de l'octroi d'Accessibilité sans relancer l'app.
//

import AppKit
import BouncerCore
import Combine
import SwiftUI

// MARK: - Contrôleur de fenêtre

/// Sous-classe de NSWindow qui intercepte Escape (cancelOperation) pour fermer la fenêtre
/// proprement, indispensable dans une application d'arrière-plan (LSUIElement) sans menu Fichier.
private final class FenetreAccueilWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

@MainActor
final class FenetreAccueilController: NSObject, NSWindowDelegate {
    private static let cleVue = "bouncer.accueilVu"

    private let windowManager: WindowManager
    private let defaults: UserDefaults
    private var fenetre: NSWindow?

    init(windowManager: WindowManager, defaults: UserDefaults = .standard) {
        self.windowManager = windowManager
        self.defaults = defaults
        super.init()
    }

    /// Affiche le guide uniquement si l'utilisateur ne l'a pas encore refermé une première fois.
    func afficherSiPremierLancement() {
        guard !defaults.bool(forKey: Self.cleVue) else { return }
        afficher()
    }

    /// Ouvre ou ramène la fenêtre au premier plan (déclenché aussi depuis le menu de l'app).
    func afficher() {
        if let fenetre {
            fenetre.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hote = NSHostingController(
            rootView: VueAccueil(windowManager: windowManager, fermer: { [weak self] in
                self?.fenetre?.performClose(nil)
            })
        )
        hote.sizingOptions = .preferredContentSize

        let fenetre = FenetreAccueilWindow(contentViewController: hote)
        fenetre.styleMask = [.titled, .closable, .fullSizeContentView]
        fenetre.title = "Bienvenue dans Bouncer"
        fenetre.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        fenetre.titlebarAppearsTransparent = true
        fenetre.isReleasedWhenClosed = false
        fenetre.delegate = self
        fenetre.center()
        self.fenetre = fenetre

        fenetre.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        defaults.set(true, forKey: Self.cleVue)
        fenetre = nil
    }
}

// MARK: - Vue Principale

struct VueAccueil: View {
    @ObservedObject var windowManager: WindowManager
    let fermer: () -> Void

    private var etat: EtatAccueil {
        EtatAccueil(
            accessibiliteAccordee: windowManager.accessibilityTrusted,
            appsEncocheInstallees: windowManager.entreesMenu.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                blocBarreDesMenus
                blocAccessibilite
                blocGeste
                if !etat.appsAInstaller.isEmpty {
                    alerteAppsManquantes
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            Divider()
            piedDePage
        }
        .frame(width: 550)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: En-tête

    private var entete: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 5, x: 0, y: 2)

                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Bienvenue dans Bouncer")
                    .font(.system(size: 19, weight: .bold))

                Text("L'arbitre de l'encoche de votre Mac : une seule app affichée à la fois, le geste pour basculer.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 1 — Barre des menus

    private var blocBarreDesMenus: some View {
        CarteEtape(
            titre: "Dans la barre des menus, pas dans le Dock",
            icone: "menubar.rectangle",
            couleurIcone: .indigo
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bouncer tourne en arrière-plan sans fenêtre permanente (`LSUIElement`). Elle n'apparaît ni dans le Dock ni dans le sélecteur d'applications : cherchez son icône en haut à droite de l'écran.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                ApercuBarreDesMenus()
            }
        }
    }

    // MARK: 2 — Accessibilité

    private var blocAccessibilite: some View {
        CarteEtape(
            titre: etat.accessibiliteAccordee ? "Accessibilité autorisée" : "Autoriser l'Accessibilité",
            icone: etat.accessibiliteAccordee ? "checkmark.shield.fill" : "lock.shield.fill",
            couleurIcone: etat.accessibiliteAccordee ? .green : .orange,
            estValide: etat.accessibiliteAccordee
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if etat.accessibiliteAccordee {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 13.5))
                            .accessibilityHidden(true)
                        Text("Autorisation active. Bouncer peut masquer et réafficher vos fenêtres d'encoche.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } else {
                    Text("Pour régir l'affichage sans conflit, macOS exige l'accès à l'Accessibilité. Sans elle, Bouncer ne peut ni masquer ni révéler vos apps d'encoche.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button("Ouvrir les Réglages Système…") {
                            windowManager.openAccessibilitySettings()
                        }
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Ouvre la section Accessibilité des Réglages Système pour autoriser Bouncer")

                        Text("Cochez Bouncer. Détection en direct sans relancer l'app.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: 3 — Le geste

    private var blocGeste: some View {
        CarteEtape(
            titre: "Le geste : survolez l'encoche, swipez",
            icone: "hand.draw.fill",
            couleurIcone: .purple
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Amenez le curseur sur l'encoche. Un swipe horizontal à deux doigts — **vers la gauche ou vers la droite** — avance d'une app. Répéter le geste fait défiler vos apps en boucle continue.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                SimulateurNotchInteractif()

                // Les 3 piliers visuels du geste
                HStack(alignment: .top, spacing: 8) {
                    PilierGeste(
                        symbole: "cursorarrow.rays",
                        titre: "1. Survol",
                        description: "Le curseur sur l'encoche révèle les flèches ‹ ›."
                    )
                    PilierGeste(
                        symbole: "arrow.left.and.right",
                        titre: "2. Swipe ↔",
                        description: "Gauche ou droite : chaque geste avance d'un cran."
                    )
                    PilierGeste(
                        symbole: "arrow.triangle.2.circlepath",
                        titre: "3. En boucle ↺",
                        description: "Répétez le geste : le cycle tourne sans fin."
                    )
                }

                HStack(spacing: 6) {
                    Image(systemName: "cursorarrow.click")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Astuce : un clic direct sur les flèches ‹ ou › fait aussi tourner le cycle.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
        }
    }

    // MARK: Alerte apps manquantes

    private var alerteAppsManquantes: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Aucune app d'encoche installée")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Bouncer n'a rien à arbitrer pour l'instant. Installez au moins une app prise en charge — \(etat.appsAInstaller.formatted(.list(type: .or))) — et elle apparaîtra automatiquement dans le menu.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Pied de page

    private var piedDePage: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(etat.pretAServir ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7.5, height: 7.5)
                    .accessibilityHidden(true)
                Text(etat.pretAServir ? "Bouncer est prêt." : "Ce guide reste accessible depuis le menu de l'app.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Commencer", action: fermer)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Ferme ce guide et commence à utiliser Bouncer")

            // Raccourcis clavier pour fermer la fenêtre (Escape et ⌘W) dans une app LSUIElement
            Button("Fermer le guide", action: fermer)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            Button("Fermer le guide avec commande W", action: fermer)
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }
}

// MARK: - Composant Carte Étape

private struct CarteEtape<Contenu: View>: View {
    let titre: String
    let icone: String
    let couleurIcone: Color
    var estValide: Bool = false
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(couleurIcone.opacity(0.14))
                        .frame(width: 24, height: 24)

                    Image(systemName: icone)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(couleurIcone)
                }
                .accessibilityHidden(true)

                Text(titre)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if estValide {
                    Text("Actif")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Statut : Actif")
                }
            }

            contenu
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.55),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Aperçu Barre des Menus

private struct ApercuBarreDesMenus: View {
    var body: some View {
        HStack(spacing: 0) {
            // Côté gauche : menus factices
            HStack(spacing: 11) {
                Text("")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.7))
                Text("Finder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                Text("Fichier")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.leading, 12)

            Spacer()

            // Côté droit : statut & Bouncer en vedette
            HStack(spacing: 9) {
                // Icône Bouncer mise en valeur
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Bouncer")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                )
                .shadow(color: Color.accentColor.opacity(0.35), radius: 3, x: 0, y: 1)

                Image(systemName: "wifi")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Image(systemName: "battery.100")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Text("10:42")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 10)
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.8),
            in: RoundedRectangle(cornerRadius: 7.5, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("L'icône de Bouncer dans la barre des menus a la forme de deux rectangles superposés, en haut à droite de l'écran.")
    }
}

// MARK: - Simulateur Interactif d'Encoche et Geste

private struct SimulateurNotchInteractif: View {
    struct AppSimulee: Identifiable {
        let id: Int
        let nom: String
        let sousTitre: String
        let icone: String
        let couleur: Color
    }

    private let apps: [AppSimulee] = [
        AppSimulee(id: 0, nom: "Now Playing", sousTitre: "Daft Punk — One More Time", icone: "music.note", couleur: .pink),
        AppSimulee(id: 1, nom: "Boring Notch", sousTitre: "Batterie 94% · 45 W", icone: "battery.100.bolt", couleur: .green),
        AppSimulee(id: 2, nom: "Vibe Island", sousTitre: "2 notifications en attente", icone: "bell.badge.fill", couleur: .orange),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var indexActif: Int = 0
    @State private var positionDoigtsX: CGFloat = 0
    @State private var sensDernierGeste: String = "droite"
    @State private var estSurvole: Bool = false

    private let timer = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            // Visualisation de l'écran & de l'encoche
            ZStack(alignment: .top) {
                // Fond sombre simulant l'écran Retina
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.12), Color(white: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 122)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )

                // L'encoche physique (Notch)
                ZStack(alignment: .top) {
                    EncochePhysiqueShape()
                        .fill(Color.black)
                        .frame(width: 130, height: 25)
                        .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 2)

                    // Capteur caméra discret
                    Circle()
                        .fill(Color(white: 0.22))
                        .frame(width: 4.5, height: 4.5)
                        .padding(.top, 6.5)
                }
                .accessibilityHidden(true)

                // Flèches latérales ‹ et › (cliquables)
                HStack(spacing: 142) {
                    BoutonFlecheEncoche(
                        symbole: "chevron.left",
                        libelleAccessible: "Flèche gauche : faire avancer le cycle"
                    ) {
                        basculer(vers: "gauche")
                    }
                    .help("Cliquez pour faire avancer le cycle")

                    BoutonFlecheEncoche(
                        symbole: "chevron.right",
                        libelleAccessible: "Flèche droite : faire avancer le cycle"
                    ) {
                        basculer(vers: "droite")
                    }
                    .help("Cliquez pour faire avancer le cycle")
                }
                .padding(.top, 2.5)

                // Contenu de l'app sous l'encoche
                VStack(spacing: 7) {
                    Spacer().frame(height: 30)

                    let app = apps[indexActif]
                    HStack(spacing: 7) {
                        Image(systemName: app.icone)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(app.couleur)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 0.5) {
                            Text(app.nom)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white)

                            Text(app.sousTitre)
                                .font(.system(size: 9))
                                .foregroundStyle(Color(white: 0.75))
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.75))
                            .overlay(
                                Capsule()
                                    .strokeBorder(app.couleur.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 5, x: 0, y: 2)
                    .id(indexActif)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.combined(with: .scale(scale: 1.04))
                            )
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Application simulée : \(app.nom), \(app.sousTitre)")

                    Spacer().frame(height: 3)

                    // Indicateur de cycle (1, 2, 3)
                    HStack(spacing: 4.5) {
                        ForEach(apps.indices, id: \.self) { i in
                            Circle()
                                .fill(i == indexActif ? Color.white : Color.white.opacity(0.25))
                                .frame(width: i == indexActif ? 5.5 : 4, height: i == indexActif ? 5.5 : 4)
                        }
                    }
                    .accessibilityHidden(true)
                }

                // Doigts de swipe sur le trackpad
                VStack {
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(sensDernierGeste == "gauche" ? Color.accentColor : Color.white.opacity(0.3))

                        // Deux doigts qui glissent
                        HStack(spacing: 4.5) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                        }
                        .offset(x: positionDoigtsX)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(sensDernierGeste == "droite" ? Color.accentColor : Color.white.opacity(0.3))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                    .padding(.bottom, 7)
                }
                .accessibilityHidden(true)
            }
            .frame(height: 122)
            .onHover { survole in
                estSurvole = survole
            }

            // Commandes d'essai interactif
            HStack {
                HStack(spacing: 4) {
                    Text("Dynamique :")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("swipe \(sensDernierGeste) ➔ avance à l'app suivante")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Button {
                    basculer(vers: "gauche")
                } label: {
                    Label("Swipe ⟵", systemImage: "hand.point.left")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Simuler un swipe vers la gauche")
                .accessibilityHint("Fait avancer le cycle à l'application suivante")

                Button {
                    basculer(vers: "droite")
                } label: {
                    Label("Swipe ⟶", systemImage: "hand.point.right")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Simuler un swipe vers la droite")
                .accessibilityHint("Fait avancer le cycle à l'application suivante")
            }
        }
        .onReceive(timer) { _ in
            guard !reduceMotion && !estSurvole else { return }
            animerSwipeAutomatique()
        }
    }

    private func basculer(vers sens: String) {
        sensDernierGeste = sens
        if reduceMotion {
            indexActif = (indexActif + 1) % apps.count
            positionDoigtsX = 0
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                indexActif = (indexActif + 1) % apps.count
                positionDoigtsX = sens == "droite" ? 16 : -16
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.18)) {
                    positionDoigtsX = 0
                }
            }
        }
    }

    private func animerSwipeAutomatique() {
        let nouveauSens = sensDernierGeste == "droite" ? "gauche" : "droite"
        basculer(vers: nouveauSens)
    }
}

// MARK: - Découpe de l'Encoche Physique

private struct EncochePhysiqueShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 8

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

// MARK: - Bouton Flèche de l'Encoche

private struct BoutonFlecheEncoche: View {
    let symbole: String
    let libelleAccessible: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var estFocus: Bool
    @State private var survol: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 21, height: 21)
                .background(
                    Circle()
                        .fill(Color(white: 0.20).opacity(survol ? 0.95 : 0.70))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            estFocus ? Color.accentColor : Color.white.opacity(survol ? 0.4 : 0.15),
                            lineWidth: estFocus ? 2 : 1
                        )
                )
                .scaleEffect(reduceMotion ? 1.0 : (survol || estFocus ? 1.08 : 1.0))
        }
        .buttonStyle(.plain)
        .focused($estFocus)
        .accessibilityLabel(libelleAccessible)
        .accessibilityHint("Fait avancer le cycle d'applications")
        .onHover { s in
            if reduceMotion {
                survol = s
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    survol = s
                }
            }
        }
    }
}

// MARK: - Piliers Explicatifs du Geste

private struct PilierGeste: View {
    let symbole: String
    let titre: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4.5) {
                Image(systemName: symbole)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text(titre)
                    .font(.system(size: 11, weight: .bold))
            }

            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.65),
            in: RoundedRectangle(cornerRadius: 7.5, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
