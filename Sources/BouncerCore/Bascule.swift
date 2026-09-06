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
    /// La cible occupe l'encoche ; la précédente a reçu la demande de fermeture et n'était pas
    /// encore partie à la fin de la fenêtre de courtoisie. Les deux se partagent l'encoche EN
    /// ATTENDANT — une feuille « Enregistrer les modifications ? » attend peut-être l'utilisateur.
    ///
    /// **Ce n'est pas un verdict final, c'est une main rendue.** L'appelant DOIT enchaîner sur
    /// `poursuivreFermeture(de:puisRelancer:)` : c'est elle qui constate la mort quand elle
    /// arrive, si tard soit-elle, et qui rend alors `.reussie`.
    case precedenteFermetureEnCours
    /// La cible n'a pas pu être démarrée — désinstallée, ou lancement refusé par le système.
    case lancementImpossible
    /// La cible s'est lancée mais sa fenêtre n'est jamais apparue dans le délai imparti.
    case cibleJamaisApparue
    /// La cible a dû être QUITTÉE pour être relancée (son démasquage ne ramenait plus rien à
    /// l'écran) et elle n'était pas encore morte à la fin de la fenêtre de courtoisie.
    ///
    /// **C'est l'état le plus dangereux du produit, et c'est pour ça qu'il a son propre verdict.**
    /// Le process a reçu son `terminate()` : l'app est déjà perdue pour l'utilisateur, et seule
    /// une relance la lui rend. `poursuivreFermeture(de:puisRelancer: true)` est cette relance, et
    /// l'appelant DOIT l'enchaîner — sans elle, ce verdict décrit une app tuée que rien ne
    /// ramènera. À traduire par un message d'ATTENTE, jamais par un message d'échec.
    case cibleFermetureEnCours
    /// Rien n'a été tenté : ce process n'a jamais eu le droit Accessibilité, et sans lui la
    /// bascule n'aurait eu que le meurtre du process à offrir. Cf. le garde de `basculer`.
    case accessibiliteJamaisAccordee
    /// Rien n'a été tenté : plus aucun écran connecté ne porte d'encoche, donc la seule mesure sur
    /// laquelle la bascule s'appuie — « cette fenêtre est-elle dans l'encoche ? » — n'a plus de
    /// réponse. Cf. le garde de `basculer`.
    case encocheIndisponible
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
    /// La fenêtre de COURTOISIE de l'attente de mort — la limite de ce que le geste de
    /// l'utilisateur patiente, jamais celle de ce que Bouncer doit à une app qu'il a tuée.
    /// Séparée de `delaiMax` : cf. `quitterEtAttendre`.
    private let delaiMort: Duration
    /// Injectable au même titre que le contrôleur, et pour la même raison : la machine à états
    /// doit pouvoir être jouée sans droits système réels.
    private let trustAccorde: @MainActor () -> Bool
    /// Même raison, même forme : les tests doivent pouvoir jouer « l'écran à encoche vient d'être
    /// débranché » sans débrancher d'écran.
    private let encocheMesurable: @MainActor () -> Bool

    public init(controleur: any ControleurApps,
                intervalleSondage: Duration = .milliseconds(50),
                delaiMax: Duration = .seconds(5),
                delaiMort: Duration = .milliseconds(600),
                trustAccorde: @escaping @MainActor () -> Bool = accessibiliteDejaAccordee,
                encocheMesurable: @escaping @MainActor () -> Bool = { zoneEncoche() != nil }) {
        self.controleur = controleur
        self.intervalleSondage = intervalleSondage
        self.delaiMax = delaiMax
        self.delaiMort = delaiMort
        self.trustAccorde = trustAccorde
        self.encocheMesurable = encocheMesurable
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

        // LE second garde, posé au même endroit et pour la même raison.
        //
        // **La condition exacte.** `zoneEncoche()` cherche un `NSScreen` dont
        // `safeAreaInsets.top > 0` ; sans lui, elle rend `nil`. Ce n'est pas un cas exotique :
        // écran à encoche débranché ou capot fermé, écrans pas encore réénumérés au réveil, Mac
        // sans encoche piloté sur un écran externe. Bouncer tourne pendant tout ça.
        //
        // **Ce que ça cassait.** `fenetreVisibleDansNotch` part de `zoneEncoche()` et rend `false`
        // dès qu'elle est `nil` — pour TOUS les pids, sans distinguer « mesurée absente » de « pas
        // mesurable ». La voie rapide de `allumer` lisait ce `false` comme « le démasquage n'a rien
        // ramené », c'est-à-dire comme son pire scénario, et appliquait son dernier recours : tuer
        // la cible pour la relancer. Puis la relance sondait la même géométrie absente, expirait au
        // bout du délai, et rendait `.cibleJamaisApparue`. Résultat : **chaque geste tuait puis
        // relançait l'app d'encoche de l'utilisateur**, en échouant à chaque fois. La garantie
        // affichée du produit — allumer avant d'éteindre, jamais d'encoche vide — n'y survivait pas,
        // parce qu'elle suppose une encoche où mesurer.
        //
        // **Pourquoi bloquer plutôt que dégrader vers le masquage.** Sans géométrie, aucune issue
        // n'est vérifiable : `allumer` ne peut pas constater que la cible est arrivée, `eteindre`
        // ne peut pas constater que la précédente est partie. Une bascule dont on ne peut rien
        // mesurer n'est pas une bascule dégradée, c'est un geste aveugle sur les process de
        // l'utilisateur. On ne tente rien, on le dit, et l'encoche — celle qui reviendra au
        // rebranchement — est laissée exactement dans l'état où l'utilisateur l'avait.
        guard encocheMesurable() else { return .encocheIndisponible }

        if actuelle?.bundleID == cible.bundleID {
            if let pid = controleur.pid(pour: cible.bundleID), controleur.fenetreVisibleDansNotch(pid: pid) {
                return await eteindre(cible)
            }
            return await allumer(cible)
        }

        let resultat = await allumer(cible)
        guard resultat == .reussie else { return resultat } // l'actuelle n'a pas été touchée
        guard let actuelle else { return .reussie }
        return await eteindre(actuelle)
    }

    // MARK: - Quitter, et le vérifier

    /// Demande la fermeture du process et ne rend la main qu'une fois qu'il est VRAIMENT parti —
    /// ou, au bout de la fenêtre de courtoisie, `false` pour dire « pas ENCORE parti ». Jamais
    /// « renoncé » : c'est `poursuivreFermeture` qui prend le relais, sans plafond.
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
    /// **Le plafond n'est PAS un abandon : c'est la limite de ce que le GESTE attend.**
    /// Ici commence la fenêtre de courtoisie, et elle ne décide que d'une chose — qui patiente,
    /// l'utilisateur ou Bouncer. Elle ne décide jamais du sort de l'app.
    ///
    /// **Ce que le plafond nu coûtait (QA passe 4, D2).** `fb1bdde` a ramené cette attente de 5 s
    /// à 600 ms pour une bonne raison — une app qui refuse de quitter verrouillait le geste 5 s en
    /// silence — mais en gardant l'ABANDON au bout. Or `tuer(pid:)` part AVANT la boucle : quand
    /// le plafond expire, l'app est déjà tuée et rien ne la relance. Le raisonnement « abandonner,
    /// c'est le chemin qui ne touche à rien » était faux, et raccourcir le plafond n'a pas fermé
    /// l'enveloppe du défaut, il l'a rendue huit fois plus étroite — donc huit fois plus facile à
    /// atteindre. Rejeu sur le double aux durées de production, cible mourant en 620 ms :
    /// `.cibleJamaisApparue`, journal `[masque(false), tue]`, PAS DE RELANCE.
    ///
    /// **Et aucune durée n'aurait suffi**, parce que la mesure qui justifiait les 600 ms était
    /// trop étroite : refaite sur un bundle AppKit cobaye, elle donne 53,6 à 87,6 ms à vide (le
    /// maximum dépasse déjà les 58,3 ms annoncés) et **867 à 894 ms dès que l'app a 800 ms de
    /// travail dans `applicationWillTerminate`** — 0 sur 4 sous le plafond. Une app d'encoche qui
    /// sauve son état en quittant est exactement ce cas. Un plafond ne borne pas la mort d'un
    /// process, il borne la patience de celui qui l'attend.
    ///
    /// **La règle qui remplace l'abandon : on ne rend jamais la main sur un process qu'on a tué
    /// sans constater sa mort.** Ce que la fenêtre de courtoisie rend tôt, c'est la main À
    /// L'UTILISATEUR — le verdict `.cibleFermetureEnCours` / `.precedenteFermetureEnCours` dit
    /// très exactement ça — et la surveillance, elle, se poursuit sans plafond dans
    /// `poursuivreFermeture`. Le défaut N3 (5 s de verrou muet par geste raté) est réglé par
    /// l'endroit où il était : le silence, pas la durée. Cf. `WindowManager.basculer`, qui allume
    /// le sablier de la barre des menus pendant le geste et publie l'attente ensuite.
    ///
    /// 600 ms restent le bon seuil de courtoisie : dix fois le cas à vide mesuré, et sous la
    /// seconde que `docs/COMPATIBILITE.md` documente pour la voie cycle de vie entière.
    ///
    /// Rend `true` si la mort a été constatée DANS la fenêtre de courtoisie — le cas de tous les
    /// jours, 53 à 88 ms. `false` veut dire « pas encore », jamais « renoncé ».
    private func quitterEtAttendre(bundleID: String, pid: pid_t) async -> Bool {
        _ = controleur.tuer(pid: pid)
        let echeance = ContinuousClock.now + delaiMort
        while controleur.pid(pour: bundleID) != nil {
            guard ContinuousClock.now < echeance else { return false }
            try? await Task.sleep(for: intervalleSondage)
        }
        return true
    }

    /// Reprend la surveillance là où la fenêtre de courtoisie l'a laissée, et finit le travail.
    ///
    /// **Sans plafond, et c'est le fond du correctif.** Bouncer a tué ce process ; il lui doit
    /// d'en constater la mort, quel que soit le temps que ça prend. Un second plafond ne ferait
    /// que déplacer l'enveloppe du défaut, jamais la fermer — c'est l'erreur qu'on corrige.
    ///
    /// **Sa seule sortie est l'annulation, et elle appartient à l'utilisateur.** `Task.isCancelled`
    /// n'est vrai que lorsqu'un geste suivant a repris la main (`WindowManager.basculer` annule la
    /// surveillance en cours avant d'en lancer une autre). C'est le bon arbitrage : relancer une
    /// app que l'utilisateur vient d'abandonner pour une autre en mettrait DEUX dans l'encoche,
    /// c'est-à-dire le problème même que Bouncer existe pour résoudre. Le dernier geste gagne, et
    /// l'app tuée reste au catalogue, à un clic.
    ///
    /// `puisRelancer` distingue les deux dettes, parce qu'elles ne sont pas de même nature :
    ///   - la CIBLE a été tuée POUR être relancée (repli de `allumer`) — sans relance elle est
    ///     perdue, donc on repasse par `allumer`, qui repart cette fois d'un `pid(pour:) == nil`
    ///     et prend donc la voie cycle de vie sur un process neuf ;
    ///   - la PRÉCÉDENTE, elle, n'a rien à relancer : sa mort libère l'encoche à elle seule. Ce
    ///     qu'on doit à l'utilisateur ici, c'est de retirer un message d'échec qui n'est plus
    ///     vrai — le triangle d'alerte allumé pour une app partie depuis.
    public func poursuivreFermeture(de app: NotchAppInfo, puisRelancer: Bool) async -> ResultatBascule {
        let enCours: ResultatBascule = puisRelancer ? .cibleFermetureEnCours : .precedenteFermetureEnCours
        while controleur.pid(pour: app.bundleID) != nil {
            // Avant le sommeil, pas après : `try? await Task.sleep` rend la main SUR-LE-CHAMP
            // quand la tâche est annulée, et sans ce garde la boucle tournerait à vide.
            guard !Task.isCancelled else { return enCours }
            try? await Task.sleep(for: intervalleSondage)
        }
        guard puisRelancer else { return .reussie }
        return await allumer(app)
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
            // redémarre rien (cf. `quitterEtAttendre`), et l'app serait perdue.
            //
            // Et si elle n'est pas morte au bout de la fenêtre de courtoisie, on n'abandonne PAS :
            // le `terminate()` est déjà parti, l'app est déjà perdue pour l'utilisateur, et
            // renoncer ici la laisserait morte pour de bon (QA passe 4, D2 — cible mourant en
            // 620 ms). On rend la main à l'utilisateur, et on dit que la fermeture est en cours :
            // c'est `poursuivreFermeture` qui constatera la mort et relancera, si tard soit-elle.
            guard await quitterEtAttendre(bundleID: cible.bundleID, pid: pid) else {
                return .cibleFermetureEnCours
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
    /// Rend `.precedenteFermetureEnCours` dans le seul cas où l'encoche n'est pas ENCORE libérée :
    /// le process a reçu la demande de fermeture et il est toujours là au bout de la fenêtre de
    /// courtoisie. C'est un constat mesuré, du même ordre que celui de `masquer` — et un constat
    /// daté, pas un verdict : la QA a relevé des fermetures à 867-894 ms, qui rendaient ici un
    /// échec définitif alors que l'app partait quelques centaines de millisecondes plus tard.
    /// C'est `poursuivreFermeture` qui tranche pour de bon. Masquée, quittée ou déjà arrêtée, les
    /// trois autres issues libèrent l'encoche sur-le-champ et rendent `.reussie`.
    private func eteindre(_ actuelle: NotchAppInfo) async -> ResultatBascule {
        guard let pid = controleur.pid(pour: actuelle.bundleID) else { return .reussie }
        if actuelle.support != .unsupported, await controleur.masquer(true, pid: pid) { return .reussie }
        return await quitterEtAttendre(bundleID: actuelle.bundleID, pid: pid)
            ? .reussie : .precedenteFermetureEnCours
    }
}
