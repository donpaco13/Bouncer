//
// FenetreAccueil.swift — Milestone 3 : la fenêtre de première ouverture.
//
// Le problème qu'elle règle : Bouncer est `LSUIElement = true`. Pas d'icône dans le Dock, pas de
// fenêtre, rien. Au premier lancement, un inconnu ne voit QUE le dialogue système d'Accessibilité
// levé par `WindowManager.init` — s'il le rejette, l'app est inerte et rien ne le lui dit ; s'il
// l'accorde, il ignore toujours que le geste du produit est « survoler l'encoche et swiper à deux
// doigts », qui n'est écrit nulle part ailleurs dans l'interface.
//
// Trois choses à faire comprendre, dans cet ordre : où vit l'app, l'autorisation, le geste.
// Une seule fenêtre, les trois blocs visibles d'un coup — pas d'assistant paginé : il y a trois
// paragraphes à lire, et un « Suivant » à cliquer trois fois n'ajoute que du geste.
//
// Ce que cette fenêtre NE fait PAS, et c'est intentionnel :
//   - elle ne lève AUCUN second dialogue système : `WindowManager.init` a déjà fait cet appel,
//     à froid et une seule fois ;
//   - elle ne touche AUCUNE API Accessibility. Un appel AX passé par ce process avant l'octroi du
//     trust laisse sa connexion Accessibility hors service pour le reste de sa vie (mesuré, cf.
//     WindowManager.swift:270-277). Elle ne fait que lire le `@Published accessibilityTrusted` ;
//   - elle ne demande jamais de relancer l'app : `refreshTrustState()` resonde le trust toutes les
//     2 s, la publication SwiftUI fait avancer le bloc 2 toute seule au moment où l'utilisateur
//     coche Bouncer dans les Réglages ;
//   - elle ne réécrit pas la liste des apps d'encoche : les noms viennent de `appsEncocheConnues`
//     (CatalogueApps.swift), la même table qui amorce le catalogue.

import AppKit
import BouncerCore
import SwiftUI

// MARK: - Contrôleur de fenêtre

/// Une NSWindow ordinaire, pas un NSPanel : la règle « NSPanel non-activating » de CLAUDE.md vise
/// l'overlay de l'encoche, qui ne doit jamais voler le focus. L'accueil, lui, est là pour être lu
/// et cliqué — il DOIT pouvoir devenir la fenêtre clé. `NSApp.activate` est donc nécessaire :
/// une app accessoire (`LSUIElement`) ne passe pas au premier plan toute seule.
@MainActor
final class FenetreAccueilController: NSObject, NSWindowDelegate {
    /// Vu une fois, plus jamais rouvert tout seul. Reste atteignable par le menu.
    private static let cleVue = "bouncer.accueilVu"

    private let windowManager: WindowManager
    private let defaults: UserDefaults
    private var fenetre: NSWindow?

    init(windowManager: WindowManager, defaults: UserDefaults = .standard) {
        self.windowManager = windowManager
        self.defaults = defaults
        super.init()
    }

    /// Au lancement. N'affiche rien si l'accueil a déjà été refermé une fois.
    func afficherSiPremierLancement() {
        guard !defaults.bool(forKey: Self.cleVue) else { return }
        afficher()
    }

    /// Sur demande explicite (entrée de menu). Ramène la fenêtre existante plutôt que d'en ouvrir
    /// une seconde.
    func afficher() {
        if let fenetre {
            fenetre.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // `NSHostingController` + `.preferredContentSize` : la fenêtre SUIT la taille du contenu,
        // au lieu d'être figée à l'ouverture. C'est nécessaire, pas cosmétique — le bloc 2 perd
        // son bouton et son paragraphe d'explication à la seconde où l'autorisation est accordée,
        // et une hauteur figée laisserait un vide en bas (ou, dans l'autre sens, rognerait le
        // texte). Aucune hauteur en dur nulle part.
        let hote = NSHostingController(
            rootView: VueAccueil(windowManager: windowManager, fermer: { [weak self] in
                self?.fenetre?.performClose(nil)
            })
        )
        hote.sizingOptions = .preferredContentSize

        let fenetre = NSWindow(contentViewController: hote)
        fenetre.styleMask = [.titled, .closable, .fullSizeContentView]
        fenetre.title = "Bienvenue dans Bouncer"
        // La barre des menus est présente sur TOUS les Espaces (Mission Control) : le guide se
        // rouvre donc depuis n'importe lequel. Sans `.moveToActiveSpace`, macOS renvoie à l'Espace
        // où la fenêtre a été créée au lieu de l'amener ici — et une app `LSUIElement` n'a ni
        // icône de Dock ni entrée de sélecteur pour la retrouver si on la perd de vue.
        fenetre.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        fenetre.titlebarAppearsTransparent = true
        // Sans ça, refermer la fenêtre la libère alors qu'on en garde une référence forte.
        fenetre.isReleasedWhenClosed = false
        fenetre.delegate = self
        fenetre.center()
        self.fenetre = fenetre

        fenetre.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Refermer vaut « j'ai lu ». On marque à la fermeture et pas à l'ouverture : quelqu'un qui
    /// quitte l'app sans avoir lu la retrouve au lancement suivant.
    func windowWillClose(_ notification: Notification) {
        defaults.set(true, forKey: Self.cleVue)
        fenetre = nil
    }
}

// MARK: - Vue

struct VueAccueil: View {
    @ObservedObject var windowManager: WindowManager
    let fermer: () -> Void

    /// Recalculé à chaque publication de `windowManager` — c'est ce qui fait avancer le bloc 2
    /// sans que l'utilisateur ait à revenir cliquer quoi que ce soit.
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
            VStack(alignment: .leading, spacing: 26) {
                blocBarreDesMenus
                blocAccessibilite
                blocGeste
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            Divider()
            piedDePage
        }
        .frame(width: 520)
    }

    // MARK: En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bienvenue dans Bouncer")
                .font(.system(size: 22, weight: .semibold))
            Text("Plusieurs apps veulent occuper l'encoche de votre Mac, et elles s'y superposent. Bouncer les arbitre : une seule à la fois, celle que vous désignez.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        // Titre de fenêtre transparent : la marge du haut laisse la place aux pastilles.
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 1 — où vit l'app

    private var blocBarreDesMenus: some View {
        Bloc(numero: 1, titre: "Bouncer vit dans la barre des menus") {
            Text("Il n'apparaît ni dans le Dock ni dans le sélecteur d'apps : c'est un utilitaire d'arrière-plan. Son icône, en haut à droite de l'écran, ouvre la liste de vos apps d'encoche et laisse en désigner une.")
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .imageScale(.medium)
                Text("Cherchez ce symbole dans la barre des menus.")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            // Sans ça, VoiceOver annonce « Partage d'écran » — le nom que macOS donne d'office au
            // symbole `rectangle.on.rectangle` (relevé sur l'arbre AX de la fenêtre réelle). Il
            // désigne une autre fonction du système, et « ce symbole » ne renvoie alors à rien.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("L'icône de Bouncer dans la barre des menus a la forme de deux rectangles superposés.")
        }
    }

    // MARK: 2 — l'autorisation

    private var blocAccessibilite: some View {
        Bloc(numero: 2, titre: "Autorisez l'Accessibilité", fait: etat.accessibiliteAccordee) {
            Text("Masquer et réafficher la fenêtre d'une autre app passe par l'Accessibilité de macOS. Sans cette autorisation, Bouncer voit vos apps d'encoche mais ne peut rien en faire.")
                .fixedSize(horizontal: false, vertical: true)

            if etat.accessibiliteAccordee {
                Label("Autorisation accordée. Rien de plus à faire.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("Ouvrir les Réglages Système…") {
                    windowManager.openAccessibilitySettings()
                }
                .controlSize(.large)

                Text("Cochez Bouncer dans Confidentialité et sécurité › Accessibilité. Cette fenêtre s'en aperçoit toute seule : il n'y a pas à relancer l'app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 3 — le geste

    private var blocGeste: some View {
        Bloc(numero: 3, titre: "Le geste : survolez l'encoche, swipez") {
            Text("Amenez le curseur sur l'encoche : deux flèches apparaissent de part et d'autre. Un swipe horizontal à deux doigts sur le trackpad passe à l'app suivante — et un clic sur une flèche fait exactement la même chose.")
                .fixedSize(horizontal: false, vertical: true)

            ApercuEncoche()

            if !etat.appsAInstaller.isEmpty {
                Label {
                    Text("Aucune app d'encoche n'est installée sur ce Mac : Bouncer n'a rien à arbitrer pour l'instant. Installez-en au moins une — \(etat.appsAInstaller.formatted(.list(type: .or))) — et elle apparaîtra dans le menu.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Pied de page

    private var piedDePage: some View {
        HStack {
            Text(etat.pretAServir
                 ? "Tout est prêt."
                 : "Vous pourrez rouvrir ce guide depuis le menu de Bouncer.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Commencer", action: fermer)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}

// MARK: - Pièces d'interface

/// Un bloc numéroté. La pastille passe à la coche quand l'étape est faite — seul le bloc 2 a un
/// état, les deux autres sont de la lecture.
private struct Bloc<Contenu: View>: View {
    let numero: Int
    let titre: String
    var fait: Bool = false
    @ViewBuilder let contenu: Contenu

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(fait ? Color.green : Color.accentColor)
                    .frame(width: 24, height: 24)
                if fait {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(numero)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(titre)
                    .font(.system(size: 15, weight: .semibold))
                    // La pastille (numéro ou coche) est décorative ; son sens se redit ici.
                    .accessibilityLabel(fait
                        ? "Étape \(numero), faite : \(titre)"
                        : "Étape \(numero) : \(titre)")
                contenu
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Pas de `.accessibilityElement(children: .combine)` ici : fusionner le bloc engloutirait
        // le bouton « Ouvrir les Réglages Système… », c'est-à-dire le seul contrôle dont dépend
        // celui qui n'a pas encore autorisé l'Accessibilité — précisément notre lecteur.
    }
}

/// Le haut de l'écran, l'encoche, et les flèches là où elles apparaissent vraiment : dans les
/// marges VISIBLES de part et d'autre du boîtier caméra, pas dessus (cf. NotchOverlay.swift).
/// Dessiné plutôt que capturé : une capture d'écran vieillirait au premier changement de l'app.
private struct ApercuEncoche: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))

            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 108, height: 22)
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Aperçu : l'encoche encadrée d'une flèche vers la gauche et d'une flèche vers la droite.")
    }
}
