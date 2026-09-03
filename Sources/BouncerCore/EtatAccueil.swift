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
