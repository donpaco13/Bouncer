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

import Foundation

public struct EtatAccueil: Equatable {
    /// Recopié de `WindowManager.accessibilityTrusted`, qui est resondé toutes les 2 s. C'est ce
    /// qui fait avancer l'accueil tout seul quand l'utilisateur coche Bouncer dans les Réglages :
    /// rien à relancer, rien à recliquer.
    public let accessibiliteAccordee: Bool

    /// Noms d'apps d'encoche à installer, triés. Vide dès qu'au moins une est présente : Bouncer
    /// n'a rien à arbitrer sans elles, et c'est la seule situation où il faut le dire.
    public let appsAInstaller: [String]

    /// Plus rien à faire : l'accueil peut se refermer sans laisser une app inerte derrière lui.
    public var pretAServir: Bool { accessibiliteAccordee && appsAInstaller.isEmpty }

    public init(
        accessibiliteAccordee: Bool,
        appsEncocheInstallees: Int,
        connues: [String: String] = appsEncocheConnues
    ) {
        self.accessibiliteAccordee = accessibiliteAccordee
        appsAInstaller = appsEncocheInstallees > 0
            ? []
            : connues.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
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
