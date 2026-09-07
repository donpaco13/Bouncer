//
// PiedDePageAccueil.swift — le pied de page fixe du parcours d'accueil.
//
// Extrait dans BouncerCore pour que sa géométrie réelle puisse être mesurée et testée
// directement par les tests unitaires sans instancier toute la fenêtre ni WindowManager.
//

import AppKit
import SwiftUI

// MARK: - Palette d'accueil

/// Palette du parcours d'accueil (sombre en permanence, comme l'accueil d'un Mac neuf).
public enum Nuit {
    public static let fond = LinearGradient(
        colors: [
            Color(red: 0.055, green: 0.094, blue: 0.216),
            Color(red: 0.027, green: 0.043, blue: 0.118),
            Color(red: 0.016, green: 0.024, blue: 0.071),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    public static let encre = Color.white
    public static let doux = Color.white.opacity(0.60)
    public static let tresDoux = Color.white.opacity(0.38)
    public static let trait = Color.white.opacity(0.12)
}

// MARK: - Boutons

/// Le bouton clair et large du bas, seul appel à l'action de chaque écran.
public struct BoutonPrincipal: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View { Corps(configuration: configuration) }

    private struct Corps: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var survol = false

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.03, green: 0.05, blue: 0.13))
                .frame(maxWidth: 300)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(Nuit.encre.opacity(configuration.isPressed ? 0.82 : (survol ? 1 : 0.94)))
                )
                .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
                .onHover { survol = $0 }
        }
    }
}

// MARK: - Points de pagination

/// Les cinq points du bas : cliquables pour sauter directement à un écran, parce que ça
/// vaut mieux que quatre « Continuer » d'affilée.
public struct PointsPagination: View {
    @Binding public var etape: EtapeAccueil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(etape: Binding<EtapeAccueil>) {
        self._etape = etape
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(EtapeAccueil.allCases) { candidate in
                Button {
                    if reduceMotion {
                        etape = candidate
                    } else {
                        withAnimation(.easeInOut(duration: 0.28)) { etape = candidate }
                    }
                } label: {
                    Capsule()
                        .fill(candidate == etape ? Nuit.encre : Color.white.opacity(0.22))
                        .frame(width: candidate == etape ? 20 : 7, height: 7)
                        // La cible cliquable dépasse largement le point dessiné : 7 pt de haut,
                        // c'est sous la taille minimale d'une cible pointée.
                        .contentShape(Rectangle().inset(by: -7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(texte("welcome.pagination.step", candidate.rawValue + 1, EtapeAccueil.allCases.count))
                .accessibilityAddTraits(candidate == etape ? [.isSelected] : [])
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: etape)
    }
}

// MARK: - Pied de page

/// Pied de page fixe du parcours d'accueil, contenant le bouton d'action principal,
/// la navigation (Retour / Pagination / Passer) et le raccourci clavier ⌘W.
public struct PiedDePageAccueil: View {
    @Binding public var etape: EtapeAccueil
    public var avancer: () -> Void
    public var reculer: () -> Void
    public var fermer: () -> Void

    public init(
        etape: Binding<EtapeAccueil>,
        avancer: @escaping () -> Void = {},
        reculer: @escaping () -> Void = {},
        fermer: @escaping () -> Void = {}
    ) {
        self._etape = etape
        self.avancer = avancer
        self.reculer = reculer
        self.fermer = fermer
    }

    /// Le premier écran invite (« Commencer »), les suivants enchaînent, le dernier conclut.
    public var libelleBouton: String {
        switch etape {
        case .bienvenue: return texte("welcome.button.getStarted")
        case .pret: return texte("welcome.button.finish")
        default: return texte("welcome.button.continue")
        }
    }

    public var body: some View {
        VStack(spacing: 18) {
            Button(action: avancer) {
                Text(libelleBouton)
            }
            .buttonStyle(BoutonPrincipal())
            .keyboardShortcut(.defaultAction)

            HStack {
                // Le retour occupe sa place même sur le premier écran : sinon les points de
                // pagination se décalent d'un écran à l'autre.
                Button(action: reculer) {
                    Label(texte("welcome.button.back"), systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Nuit.doux)
                .opacity(etape.precedente == nil ? 0 : 1)
                .disabled(etape.precedente == nil)
                .accessibilityHidden(etape.precedente == nil)
                .frame(width: 92, alignment: .leading)

                Spacer()

                PointsPagination(etape: $etape)

                Spacer()

                Button(texte("welcome.button.skip"), action: fermer)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Nuit.tresDoux)
                    .opacity(etape.estDerniere ? 0 : 1)
                    .disabled(etape.estDerniere)
                    .accessibilityHidden(etape.estDerniere)
                    .frame(width: 92, alignment: .trailing)
                    .accessibilityHint(texte("welcome.skip.hint"))
            }

            // ⌘W n'a pas d'équivalent AppKit ici : une app LSUIElement n'a pas de menu Fichier
            // d'où le raccourci viendrait. Échap, lui, n'est PAS ici — `FenetreAccueilWindow`
            // l'intercepte au niveau de la fenêtre.
            Button(texte("welcome.close.commandW"), action: fermer)
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 30)
        .padding(.top, 6)
    }

    /// Mesure la hauteur réelle du pied de page rendu par AppKit / SwiftUI.
    /// MESURÉ à 127 pt (bouton 41 pt + espacement 18 pt + rangée 14 pt + espacement 18 pt vers bouton ⌘W + marges 36 pt).
    @MainActor
    public static func mesurerHauteur(
        pour etape: EtapeAccueil = .bienvenue,
        largeur: CGFloat = GeometrieAccueil.largeur
    ) -> CGFloat {
        let view = PiedDePageAccueil(etape: .constant(etape))
            .frame(width: largeur)
        let hote = NSHostingView(rootView: view)
        hote.layout()
        return hote.fittingSize.height
    }
}
