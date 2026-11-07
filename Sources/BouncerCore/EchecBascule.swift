//
// EchecBascule.swift — un échec de bascule, dit en une ligne et en entier.
//
// Le menu de la barre des menus est un NSMenu : il ne replie pas les lignes, il s'élargit jusqu'à
// la phrase la plus longue. Le message complet (jusqu'à ~330 caractères pour une révocation)
// étirait donc tout le menu sur la largeur de l'écran. Le menu montre le libellé court ; la
// phrase entière reste dans l'infobulle, et c'est elle que les tests vérifient.

import Foundation

public struct EchecBascule: Equatable, Sendable {
    /// Clé du message complet. Le libellé court porte la même clé suffixée de `.short`, et reçoit
    /// les mêmes arguments : il n'en lit que le premier, le nom de l'app quand il y en a un.
    public let cle: String
    /// Une ligne, pour le menu.
    public let court: String
    /// La phrase entière, pour l'infobulle.
    public let detail: String

    init(_ cle: String, _ arguments: CVarArg...) {
        self.cle = cle
        court = texte(cle + ".short", arguments: arguments)
        detail = texte(cle, arguments: arguments)
    }

    /// L'échec vient du droit d'Accessibilité : le seul remède est dans les Réglages Système, et
    /// le menu propose d'y aller juste en dessous.
    public var concerneAccessibilite: Bool {
        cle.hasPrefix("error.accessRevoked") || cle == "error.accessNeverGranted"
    }
}
