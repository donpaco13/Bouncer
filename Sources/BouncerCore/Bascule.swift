//
// Bascule.swift — la machine à états qui fait passer l'encoche d'une app à l'autre.
//
// Le cœur du produit. Deux méthodes selon ce que l'app accepte : masquage Accessibilité pour
// celles qui répondent, cycle de vie du process pour celles qui épinglent leurs fenêtres dans un
// Space privé et ignorent l'ordre de masquage.
//
// La règle qui commande tout le reste : **on allume la suivante avant d'éteindre la précédente**.
// L'utilisateur ne doit jamais voir une encoche vide, et un échec ne doit jamais le laisser avec
// deux apps mortes. C'est pour ça que `eteindre` n'est atteignable que par la branche où
// `allumer` a déjà réussi — la garantie est structurelle, pas une discipline d'appelant.
//
// Rien n'est écrit ici dans le modèle : la bascule agit et rend un verdict, c'est
// `WindowManager` qui met à jour `NotchAppInfo` en conséquence.
//

import Foundation

/// Ce que la bascule a obtenu. Les deux échecs se distinguent parce qu'ils ne disent pas la même
/// chose à l'utilisateur : l'un est une app disparue du disque, l'autre une app qui se lance mais
/// ne dessine rien dans l'encoche.
public enum ResultatBascule: Equatable {
    /// La cible occupe l'encoche, et la précédente a été rangée (masquée ou quittée).
    case reussie
    /// La cible n'a pas pu être démarrée — désinstallée, ou lancement refusé par le système.
    case lancementImpossible
    /// La cible s'est lancée mais sa fenêtre n'est jamais apparue dans le délai imparti.
    case cibleJamaisApparue
}

/// La séquence de bascule, indépendante de toute vraie app : tout passe par `ControleurApps`.
///
/// Les deux durées sont injectables pour que les tests ne paient pas 5 s de timeout réel. Leurs
/// valeurs par défaut sont celles du produit.
@MainActor
public struct Bascule {
    private let controleur: any ControleurApps
    private let intervalleSondage: Duration
    private let delaiMax: Duration

    public init(controleur: any ControleurApps,
                intervalleSondage: Duration = .milliseconds(50),
                delaiMax: Duration = .seconds(5)) {
        self.controleur = controleur
        self.intervalleSondage = intervalleSondage
        self.delaiMax = delaiMax
    }

    /// Fait passer l'encoche de `actuelle` à `cible`.
    ///
    /// `cible == actuelle` (le cas d'une seule app au catalogue) devient un interrupteur sur cette
    /// app : visible → on l'éteint, éteinte → on l'allume. C'est le comportement historique du
    /// clic, préservé.
    public func basculer(vers cible: NotchAppInfo, depuis actuelle: NotchAppInfo?) async -> ResultatBascule {
        if actuelle?.bundleID == cible.bundleID {
            if let pid = controleur.pid(pour: cible.bundleID), controleur.fenetreVisibleDansNotch(pid: pid) {
                eteindre(cible)
                return .reussie
            }
            return await allumer(cible)
        }

        let resultat = await allumer(cible)
        guard resultat == .reussie else { return resultat } // l'actuelle n'a pas été touchée
        if let actuelle { eteindre(actuelle) }
        return .reussie
    }

    // MARK: - Allumer la cible

    /// Amène la fenêtre de `cible` dans l'encoche, et ne rend `.reussie` qu'une fois qu'elle y est
    /// vraiment — mesuré par `fenetreVisibleDansNotch`, jamais déduit d'un code retour d'API.
    private func allumer(_ cible: NotchAppInfo) async -> ResultatBascule {
        // Voie rapide (~31 ms) : l'app est déjà chaude et se laisse démasquer.
        if cible.support == .supported, let pid = controleur.pid(pour: cible.bundleID) {
            _ = controleur.masquer(false, pid: pid)
            return controleur.fenetreVisibleDansNotch(pid: pid) ? .reussie : .cibleJamaisApparue
        }

        // Voie cycle de vie : démarrer, puis attendre que le WindowServer affiche la fenêtre.
        guard await controleur.lancer(bundleID: cible.bundleID) else { return .lancementImpossible }

        let echeance = ContinuousClock.now + delaiMax
        while true {
            if let pid = controleur.pid(pour: cible.bundleID), controleur.fenetreVisibleDansNotch(pid: pid) {
                return .reussie
            }
            guard ContinuousClock.now < echeance else { return .cibleJamaisApparue }
            try? await Task.sleep(for: intervalleSondage)
        }
    }

    // MARK: - Éteindre la précédente

    /// Libère l'encoche. Le masquage est toujours préféré — il garde l'app chaude pour la bascule
    /// suivante — et on ne quitte le process que lorsqu'il n'y a pas d'autre moyen.
    ///
    /// Une app dont le verdict est déjà `.unsupported` saute l'essai de masquage : sur elle il
    /// coûterait sa temporisation WindowServer pour rien. Pour les autres, l'échec mesuré du
    /// masquage sert de dernier filet — un verdict peut avoir vieilli, une mise à jour de l'app
    /// peut l'avoir changé, et laisser deux apps dans l'encoche serait pire que la quitter.
    private func eteindre(_ actuelle: NotchAppInfo) {
        guard let pid = controleur.pid(pour: actuelle.bundleID) else { return }
        if actuelle.support != .unsupported, controleur.masquer(true, pid: pid) { return }
        _ = controleur.tuer(pid: pid)
    }
}
