//
// EtatAccueil.swift — ce que l'écran d'accueil a encore à demander à l'utilisateur.
//
// Sorti de la vue pour une raison précise : les deux conditions qui rendent Bouncer INERTE chez
// un inconnu — l'Accessibilité pas accordée, aucune app d'encoche installée — ne se voient pas
// sur la machine de son auteur, où les deux sont vraies depuis toujours. C'est donc exactement le
// genre de logique qui ne peut être vérifiée qu'en test.
//
// Aucune API Accessibility ici, et c'est délibéré : un appel AX passé par ce process AVANT
// l'octroi du trust laisse sa connexion Accessibility hors service pour le reste de sa vie
// (mesuré, cf. WindowManager.swift). L'accueil ne fait que LIRE le drapeau que WindowManager
// publie déjà.

import CoreGraphics
import Foundation

public struct EtatAccueil: Equatable {
    /// Recopié de `WindowManager.accessibilityTrusted`, qui est resondé toutes les 2 s. C'est ce
    /// qui fait avancer l'accueil tout seul quand l'utilisateur coche Bouncer dans les Réglages :
    /// rien à relancer, rien à recliquer.
    public let accessibiliteAccordee: Bool

    /// Noms d'apps d'encoche à installer, triés. Vide dès qu'au moins une est présente : Bouncer
    /// n'a rien à arbitrer sans elles, et c'est la seule situation où il faut le dire.
    ///
    /// Plafonné à trois, parce que la phrase qui les rend est « essayez A, B ou C » sur une seule
    /// ligne de bilan : l'amorçage en compte sept depuis la campagne du 5 septembre 2026, et les
    /// énumérer tous transformerait une suggestion en inventaire qui déborde la fenêtre.
    public let appsAInstaller: [String]

    /// ponytail: trois suggestions, pas un catalogue. Si le parcours d'accueil se met un jour à
    /// LISTER les apps au lieu d'en suggérer, la mesure à relever est ce que la fenêtre affiche.
    private static let maxSuggestions = 3

    /// Une encoche est à l'écran. Faux sur un Mac sans encoche, ou capot fermé sur un écran
    /// externe : Bouncer n'a alors rien à arbitrer, quoi que dise le reste du bilan.
    public let encochePresente: Bool

    /// Une seule app d'encoche : le cycle n'a qu'un élément et devient un interrupteur — le swipe
    /// la masque puis la ramène (cf. `WindowManager.cycle(forward:)`). Ça marche, mais ce n'est
    /// pas ce que Bouncer promet, et le bilan ne doit pas le peindre en vert.
    public let uneSeuleApp: Bool

    /// Plus rien à faire : l'accueil peut se refermer sans laisser une app inerte derrière lui.
    /// C'est ce qui décide si le guide revient au lancement suivant. L'encoche et la deuxième app
    /// n'y entrent pas : l'une dépend du capot, l'autre est un conseil, et ni l'une ni l'autre ne
    /// justifie de rouvrir le guide à chaque démarrage.
    public var pretAServir: Bool { accessibiliteAccordee && appsAInstaller.isEmpty }

    /// Le bilan peut dire « Tout est en place » sans mentir.
    public var toutEnPlace: Bool { pretAServir && encochePresente && !uneSeuleApp }

    public init(
        accessibiliteAccordee: Bool,
        appsEncocheInstallees: Int,
        encochePresente: Bool = true,
        connues: [String: String] = appsEncocheConnues
    ) {
        self.accessibiliteAccordee = accessibiliteAccordee
        self.encochePresente = encochePresente
        uneSeuleApp = appsEncocheInstallees == 1
        appsAInstaller = appsEncocheInstallees > 0
            ? []
            : connues.values
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .prefix(Self.maxSuggestions)
                .map { $0 }
    }
}

public extension WindowManager {
    /// Le bilan de l'accueil, construit à un seul endroit : la vue l'affiche, le contrôleur de
    /// fenêtre s'en sert pour décider si le guide reviendra au prochain lancement.
    var etatAccueil: EtatAccueil {
        EtatAccueil(
            accessibiliteAccordee: accessibilityTrusted,
            appsEncocheInstallees: entreesMenu.count,
            encochePresente: encochePresente
        )
    }

    /// Lu sur la description que le sondage publie déjà (`notch.none` quand `zoneEncoche()` ne
    /// trouve rien) : pas de seconde détection, et l'accueil se met à jour au même rythme.
    var encochePresente: Bool { lastNotchZoneDescription != texte("notch.none") }
}

/// Les cinq écrans du parcours d'accueil, dans l'ordre de lecture.
///
/// Ici et non dans la vue pour une raison unique : l'avance et le retour se bornent aux
/// extrémités, et une borne fausse ne se voit qu'en cliquant « Continuer » sur le DERNIER écran
/// ou « Retour » sur le premier — deux gestes qu'on ne fait jamais en développant. Les bornes
/// sont déléguées à `init?(rawValue:)`, qui rend `nil` hors plage : il n'y a pas de `min`/`max`
/// à écrire, donc pas de décalage d'un cran à écrire de travers.
public enum EtapeAccueil: Int, CaseIterable, Identifiable, Sendable {
    case bienvenue
    case probleme
    case accessibilite
    case geste
    case pret

    public var id: Int { rawValue }
    public var suivante: EtapeAccueil? { EtapeAccueil(rawValue: rawValue + 1) }
    public var precedente: EtapeAccueil? { EtapeAccueil(rawValue: rawValue - 1) }
    public var estDerniere: Bool { suivante == nil }
}

/// Géométrie et seuils de la fenêtre d'accueil.
///
/// Mesurés et extraits dans BouncerCore pour qu'un test puisse vérifier les seuils
/// d'écrêtage et de débordement d'écran sans dépendre de l'affichage de la machine de test
/// (`visibleFrame.height = 780` sur la machine de référence, ce qui masque tout débordement).
public enum GeometrieAccueil {
    public static let largeur: CGFloat = 660
    public static let hauteurVoulue: CGFloat = 580
    /// Plancher de hauteur de contenu : 320 pt (comme en passe 1). Un plancher à 460 pt rendait
    /// la fenêtre plus haute que l'écran dès que visibleFrame.height passait sous 512 pt.
    public static let plancherHauteur: CGFloat = 320
    public static let margeRespiration: CGFloat = 24
    public static let hauteurBarreDeTitre: CGFloat = 28
    public static let margePastillesHaut: CGFloat = 34
    /// Hauteur mesurée du pied de page (bouton principal 41 pt + espacement 18 pt + rangée
    /// de navigation 14 pt + espacement vers bouton masqué ⌘W 18 pt + marges 36 pt = 127 pt).
    /// MESURÉ par `PiedDePageAccueil.mesurerHauteur()` et verrouillé par `PiedDePageTests` :
    /// l'ancienne constante déclarée à 115 pt omettait l'espacement vers le bouton ⌘W.
    public static let hauteurPiedDePage: CGFloat = 127

    /// Hauteur minimale hors contenu (pastilles en haut + boutons et pagination en bas).
    public static var hauteurFixe: CGFloat {
        margePastillesHaut + hauteurPiedDePage
    }

    /// Hauteur utile disponible pour le contenu de l'étape pour une hauteur de fenêtre donnée.
    public static func hauteurUtile(pourHauteurFenetre hauteur: CGFloat) -> CGFloat {
        max(0, hauteur - hauteurFixe)
    }

    /// Calcule la hauteur allouée au contenu de la fenêtre d'accueil en fonction de la hauteur
    /// visible de l'écran (`visibleFrame.height`).
    public static func hauteurContenu(
        visibleFrameHeight: CGFloat,
        barreDeTitre: CGFloat = hauteurBarreDeTitre,
        respiration: CGFloat = margeRespiration
    ) -> CGFloat {
        let plafond = visibleFrameHeight - barreDeTitre - respiration
        return max(plancherHauteur, min(hauteurVoulue, plafond))
    }

    /// Hauteur intrinsèque minimale du contenu de l'étape.
    ///
    /// Pour `.bienvenue`, le tracé vectoriel « hello » mesure 187 pt de haut (contre 132 pt pour
    /// l'ancien tracé dessiné à la main), soit 290 pt de contenu avec les textes et espacements.
    public static func hauteurMinimaleContenu(pour etape: EtapeAccueil) -> CGFloat {
        switch etape {
        case .bienvenue:
            // hello: 187 + padding bas: 26 + titre: 31 + sous-titre: 46 = 290 pt
            return 290
        case .probleme:
            // illustration: 150 + padding: 28 + titre: 31 + sous-titre: 63 = 272 pt
            return 272
        case .accessibilite:
            // sceau: 72 + padding: 26 + titre: 31 + sous-titre: 46 + bouton/texte: 65 = 240 pt
            return 240
        case .geste:
            // simulateur: 122 + padding: 22 + titre: 31 + sous-titre: 46 + raccourci: 39 = 260 pt
            return 260
        case .pret:
            // sceau: 72 + padding: 22 + titre: 31 + bilan: 66 (trois lignes, encoche absente)
            // + apercu: 57 = 248 pt
            return 248
        }
    }

    /// Hauteur totale minimale de la fenêtre requise pour afficher l'étape sans défilement.
    public static func hauteurMinimaleFenetreSansDefilement(pour etape: EtapeAccueil) -> CGFloat {
        hauteurFixe + hauteurMinimaleContenu(pour: etape)
    }

    /// Hauteur minimale de `visibleFrame` nécessaire pour que la fenêtre tienne sans défilement
    /// (avec barre de titre et 24 pt de respiration).
    public static func seuilVisibleFrameSansDefilement(
        pour etape: EtapeAccueil,
        barreDeTitre: CGFloat = hauteurBarreDeTitre,
        respiration: CGFloat = margeRespiration
    ) -> CGFloat {
        hauteurMinimaleFenetreSansDefilement(pour: etape) + barreDeTitre + respiration
    }
}

