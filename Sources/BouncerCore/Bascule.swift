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
    /// La cible occupe l'encoche, mais la précédente n'a pas pu être quittée : elle a accepté la
    /// demande de fermeture sans jamais mourir — une feuille « Enregistrer les modifications ? »
    /// attend l'utilisateur, ou l'app ne répond plus. Les deux se partagent l'encoche.
    case precedenteResteEnPlace
    /// La cible n'a pas pu être démarrée — désinstallée, ou lancement refusé par le système.
    case lancementImpossible
    /// La cible s'est lancée mais sa fenêtre n'est jamais apparue dans le délai imparti.
    case cibleJamaisApparue
    /// Rien n'a été tenté : ce process n'a jamais eu le droit Accessibilité, et sans lui la
    /// bascule n'aurait eu que le meurtre du process à offrir. Cf. le garde de `basculer`.
    case accessibiliteJamaisAccordee
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
    /// Injectable au même titre que le contrôleur, et pour la même raison : la machine à états
    /// doit pouvoir être jouée sans droits système réels.
    private let trustAccorde: @MainActor () -> Bool

    public init(controleur: any ControleurApps,
                intervalleSondage: Duration = .milliseconds(50),
                delaiMax: Duration = .seconds(5),
                trustAccorde: @escaping @MainActor () -> Bool = accessibiliteDejaAccordee) {
        self.controleur = controleur
        self.intervalleSondage = intervalleSondage
        self.delaiMax = delaiMax
        self.trustAccorde = trustAccorde
    }

    /// Fait passer l'encoche de `actuelle` à `cible`.
    ///
    /// `cible == actuelle` (le cas d'une seule app au catalogue) devient un interrupteur sur cette
    /// app : visible → on l'éteint, éteinte → on l'allume. C'est le comportement historique du
    /// clic, préservé.
    public func basculer(vers cible: NotchAppInfo, depuis actuelle: NotchAppInfo?) async -> ResultatBascule {
        // LE garde du chemin AX, posé ici et à un seul endroit.
        //
        // **Pourquoi cette couche.** `allumer` et `eteindre` touchent tous deux l'API AX, et ils
        // ne sont atteignables que par ici : un garde sur `basculer` les couvre par construction,
        // là où un garde recopié dans chacun serait un oubli en attente. Plus haut, dans
        // `WindowManager.basculer`, il protégerait les gestes d'aujourd'hui mais pas un futur
        // appelant de cette machine à états. Plus bas, dans `ControleurAppsSysteme.masquer`, il ne
        // pourrait que rendre `false` — ce qui déclencherait le repli `tuer(pid:)`, c'est-à-dire
        // très exactement le bug qu'on corrige.
        //
        // **Pourquoi bloquer au lieu de dégrader.** Sans octroi, aucune app n'a pu passer
        // `testSupport` : toutes valent `.testing`, donc `eteindre` tenterait le masquage, il
        // échouerait, et le dernier filet quitterait l'app d'encoche de l'utilisateur — tout en
        // condamnant la connexion Accessibility de Bouncer jusqu'à son prochain lancement. La
        // seule bascule possible sans le droit est destructrice ; on la refuse et on le dit.
        // C'est `WindowManager` qui traduit ce verdict en message, sur le canal `echecBascule`
        // qui fait déjà passer l'icône de la barre des menus en alerte.
        guard trustAccorde() else { return .accessibiliteJamaisAccordee }

        if actuelle?.bundleID == cible.bundleID {
            if let pid = controleur.pid(pour: cible.bundleID), controleur.fenetreVisibleDansNotch(pid: pid) {
                return await eteindre(cible) ? .reussie : .precedenteResteEnPlace
            }
            return await allumer(cible)
        }

        let resultat = await allumer(cible)
        guard resultat == .reussie else { return resultat } // l'actuelle n'a pas été touchée
        guard let actuelle else { return .reussie }
        return await eteindre(actuelle) ? .reussie : .precedenteResteEnPlace
    }

    // MARK: - Quitter, et le vérifier

    /// Demande la fermeture du process et ne rend la main qu'une fois qu'il est VRAIMENT parti.
    /// `false` s'il est encore là au bout du délai.
    ///
    /// **Pourquoi attendre — c'est le cœur de la sûreté du meurtre.** `tuer` repose sur
    /// `NSRunningApplication.terminate()`, qui poste un Apple Event et rend la main aussitôt : son
    /// `true` dit que la DEMANDE est partie, pas que l'app est morte. Son propre contrat le disait
    /// (« sonder pour le savoir ») et aucun des deux appelants ne le sondait. Chacun en payait le
    /// prix :
    ///   - `allumer` tuait la cible puis la relançait dans la foulée. `openApplication` sur un
    ///     process en train de mourir rend l'instance mourante au lieu d'en démarrer une neuve :
    ///     le sondage ne voyait jamais de fenêtre, la bascule expirait au bout du délai, et
    ///     **l'app que l'utilisateur venait de demander restait morte, sans relance**. C'est ça,
    ///     perdre une app.
    ///   - `eteindre` rendait un succès sans rien vérifier. Une app qui refuse de quitter reste
    ///     dans l'encoche à côté de la nouvelle, et `WindowManager`, ne voyant qu'un `.reussie`,
    ///     la marquait `isHiddenByUs` — un état faux, sur une app parfaitement visible.
    ///
    /// **Pas de `forceTerminate` en dernier recours.** Une app qui ne quitte pas est le plus
    /// souvent une app qui a quelque chose à enregistrer. La tuer de force ferait perdre le
    /// travail de l'utilisateur, c'est-à-dire exactement ce que ce chemin existe pour empêcher.
    /// On constate, on le dit, et on laisse l'app tranquille.
    ///
    /// Sonde `pid(pour:)` plutôt que `NSRunningApplication.isTerminated` : c'est déjà la mesure du
    /// protocole, elle traverse le double de test, et elle n'ajoute aucune API à la surface.
    ///
    /// ponytail: réutilise `delaiMax`, le même plafond que l'attente d'apparition. Une bascule
    /// peut donc coûter deux fois ce délai dans le pire cas. Si l'attente de mort mérite un
    /// plafond propre, la mesure à relever est le temps réel de fermeture d'une app d'encoche.
    private func quitterEtAttendre(bundleID: String, pid: pid_t) async -> Bool {
        _ = controleur.tuer(pid: pid)
        let echeance = ContinuousClock.now + delaiMax
        while controleur.pid(pour: bundleID) != nil {
            guard ContinuousClock.now < echeance else { return false }
            try? await Task.sleep(for: intervalleSondage)
        }
        return true
    }

    // MARK: - Allumer la cible

    /// Amène la fenêtre de `cible` dans l'encoche, et ne rend `.reussie` qu'une fois qu'elle y est
    /// vraiment — mesuré par `fenetreVisibleDansNotch`, jamais déduit d'un code retour d'API.
    private func allumer(_ cible: NotchAppInfo) async -> ResultatBascule {
        // Voie rapide (~31 ms) : l'app est déjà chaude et se laisse démasquer.
        if cible.support == .supported, let pid = controleur.pid(pour: cible.bundleID) {
            _ = await controleur.masquer(false, pid: pid)
            if controleur.fenetreVisibleDansNotch(pid: pid) { return .reussie }

            // Le démasquage n'a rien ramené à l'écran, alors que le verdict promettait le
            // contraire : le droit Accessibilité a été retiré depuis, ou une mise à jour de l'app
            // l'a rendue résistante. On ne peut PAS s'arrêter là — l'app est masquée et on ne
            // sait plus la démasquer, or une app d'encoche n'a ni icône du Dock ni entrée
            // Cmd-Tab : elle serait invisible ET introuvable, exactement le pire état possible.
            // La quitter pour la relancer par la voie cycle de vie est le seul retour, et c'est
            // le pendant exact du dernier filet de `eteindre`, qui tue déjà quand le masquage
            // mesuré échoue.
            //
            // On ATTEND la mort avant de relancer : relancer un process encore mourant ne
            // redémarre rien (cf. `quitterEtAttendre`), et l'app serait perdue. Si elle refuse de
            // mourir, elle est là sans rien dessiner dans l'encoche — ce que dit très exactement
            // `.cibleJamaisApparue`. La relancer n'y changerait rien, et l'actuelle, elle, n'a
            // toujours pas été touchée.
            guard await quitterEtAttendre(bundleID: cible.bundleID, pid: pid) else {
                return .cibleJamaisApparue
            }
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
    ///
    /// Rend `false` dans le seul cas où l'encoche n'a PAS été libérée : le process a reçu la
    /// demande de fermeture et il est toujours là. C'est un constat mesuré, du même ordre que
    /// celui de `masquer`, et c'est tout ce que l'appelant a besoin de savoir — masquée, quittée
    /// ou déjà arrêtée, les trois autres issues libèrent l'encoche.
    private func eteindre(_ actuelle: NotchAppInfo) async -> Bool {
        guard let pid = controleur.pid(pour: actuelle.bundleID) else { return true }
        if actuelle.support != .unsupported, await controleur.masquer(true, pid: pid) { return true }
        return await quitterEtAttendre(bundleID: actuelle.bundleID, pid: pid)
    }
}
