//
// BasculeDegradeeTests.swift — la machine à états quand le monde n'est plus celui du cas nominal.
//
// Deux défauts majeurs relevés par la seconde passe de QA, et jamais corrigés. Les deux naissent
// de correctifs précédents qui sont allés trop loin, et les deux se rejouent ici sur le double du
// dépôt, **aux durées de production** : c'est le seul moyen de prouver qu'on n'a pas déplacé le
// problème dans un paramètre de test.
//

import Foundation
import Testing
@testable import BouncerCore

@MainActor
private func info(_ bundleID: String, _ support: SupportStatus, pid: pid_t?) -> NotchAppInfo {
    NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
}

private let vibe = "app.vibeisland.macos"
private let boring = "theboringteam.boringnotch"
private let notchy = "dev.notchy.notchy"

/// Une bascule aux valeurs du produit : sondage 50 ms, apparition 5 s, mort 600 ms. Seuls les deux
/// gardes système sont injectés, parce qu'ils dépendraient sinon de la machine qui exécute la suite.
@MainActor
private func basculeDeProduction(
    _ double: ControleurAppsDouble, encocheMesurable: @escaping @MainActor () -> Bool = { true }
) -> Bascule {
    Bascule(controleur: double, trustAccorde: { true }, encocheMesurable: encocheMesurable)
}

// MARK: - N2 : plus d'encoche mesurable, et chaque geste tuait l'app

/// **Le défaut.** `fenetreVisibleDansNotch` part de `zoneEncoche()` et rend `false` dès qu'elle est
/// `nil` — donc pour tous les pids à la fois, sans distinguer « mesurée absente » de « pas
/// mesurable ». La voie rapide de `allumer` lisait ce `false` comme son pire scénario (« l'app est
/// masquée et je ne sais plus la démasquer ») et appliquait son dernier recours : tuer la cible
/// pour la relancer. Écran débranché, capot fermé, Mac réveillé, écran principal changé : chacun
/// de ces cas ordinaires transformait chaque geste en meurtre suivi d'un échec.
///
/// La garantie affichée du produit — allumer avant d'éteindre, jamais d'encoche vide — suppose une
/// encoche où mesurer. Sans elle, on ne tente rien.
@MainActor
struct EncocheAbsenteTests {
    @Test("Plus d'écran à encoche : la bascule ne touche à rien et le dit")
    func encocheIndisponibleNeToucheARien() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100, notchy: 300])
        double.encocheMesurable = false

        let debut = ContinuousClock.now
        let resultat = await basculeDeProduction(double, encocheMesurable: { double.encocheMesurable })
            .basculer(vers: info(vibe, .supported, pid: 100), depuis: info(notchy, .supported, pid: 300))
        let ecoule = ContinuousClock.now - debut

        #expect(resultat == .encocheIndisponible)
        // Le cœur du correctif : aucun `tue`, aucun `lance`, aucun `masque`. Rien.
        #expect(double.journal.isEmpty)
        #expect(double.pid(pour: vibe) == 100)      // même process qu'avant le geste
        #expect(double.pid(pour: notchy) == 300)
        // Et le refus est immédiat : le garde sort avant le moindre sondage.
        #expect(ecoule < .milliseconds(200))
    }

    /// Le même garde sur la branche de l'interrupteur (`cible == actuelle`, le cas d'une seule app
    /// au catalogue). Elle sonde `fenetreVisibleDansNotch` la première, donc sans garde elle
    /// concluait « éteinte » sur une app parfaitement visible et partait l'allumer — c'est-à-dire
    /// la tuer par le repli.
    @Test("Plus d'écran à encoche : l'interrupteur sur une app seule ne la tue pas non plus")
    func interrupteurAppSeuleEgalementProtege() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100])
        double.encocheMesurable = false
        let seule = info(vibe, .supported, pid: 100)

        let resultat = await basculeDeProduction(double, encocheMesurable: { double.encocheMesurable })
            .basculer(vers: seule, depuis: seule)

        #expect(resultat == .encocheIndisponible)
        #expect(double.journal.isEmpty)
        #expect(double.pid(pour: vibe) == 100)
    }

    /// Le garde n'est PAS une latche, contrairement à celui du trust Accessibilité : le droit
    /// accordé une fois ne se reprend pas, un écran rebranché revient. Rien à relancer.
    @Test("L'écran rebranché : la bascule refonctionne sans redémarrer Bouncer")
    func encocheDeNouveauMesurableRetablitLaBascule() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100, notchy: 300])
        let bascule = basculeDeProduction(double, encocheMesurable: { double.encocheMesurable })
        let cible = info(vibe, .supported, pid: 100)
        let actuelle = info(notchy, .supported, pid: 300)

        double.encocheMesurable = false
        #expect(await bascule.basculer(vers: cible, depuis: actuelle) == .encocheIndisponible)

        double.encocheMesurable = true
        #expect(await bascule.basculer(vers: cible, depuis: actuelle) == .reussie)
        #expect(double.journal == [.masque(false, 100), .masque(true, 300)])
    }

    /// **Test de non-vacuité.** Les trois précédents ne valent que si le double reproduit vraiment
    /// la panne. Ici le garde est neutralisé, le monde reste celui d'une encoche non mesurable, et
    /// on retrouve exactement le comportement d'avant le correctif : l'app de l'utilisateur est
    /// tuée puis relancée, pour finir sur un échec.
    ///
    /// Durées raccourcies, seul test du fichier à en avoir : sans le garde, ce scénario paie le
    /// délai d'apparition en entier, et c'est précisément ce qu'on ne veut plus faire payer.
    @Test("Sans le garde, l'encoche non mesurable tue puis relance la cible — le défaut, reproduit")
    func sansLeGardeLeDefautEstBienLa() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        double.encocheMesurable = false

        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(1),
                              delaiMax: .milliseconds(50), delaiMort: .milliseconds(50),
                              trustAccorde: { true }, encocheMesurable: { true })
        let resultat = await bascule.basculer(vers: info(vibe, .supported, pid: 100), depuis: nil)

        #expect(resultat == .cibleJamaisApparue)
        #expect(double.journal.contains(.tue(100)))   // le meurtre
        #expect(double.journal.contains(.lance(vibe)))// la relance
        #expect(double.pid(pour: vibe) != 100)        // ce n'est plus le process de l'utilisateur
    }
}

// MARK: - N3 : cinq secondes de verrou muet par geste raté

/// **Le défaut.** L'attente de mort est juste — `terminate()` poste un Apple Event et rend `true`
/// aussitôt, et relancer sur un process encore mourant perdait l'app pour de bon. Mais son plafond
/// était emprunté à `delaiMax`, la borne du DÉMARRAGE À FROID d'une app. Une app qui refuse de
/// quitter coûtait donc 5 s, pendant lesquelles `WindowManager.basculer` refuse tout second geste
/// sans rien afficher : l'utilisateur swipe, rien ne bouge, il resswipe, rien ne bouge.
///
/// **Le correctif ne raccourcit pas le sondage, il lui rend sa mesure.** Relevé du 6 septembre
/// 2026 sur une app AppKit sans document — la forme d'une app d'encoche : 26 à 58 ms entre
/// `terminate()` et la disparition du pid. `delaiMort` = 600 ms, dix fois le pire cas.
///
/// **Et ce raisonnement-là était faux** — c'est le défaut D2 de la QA passe 4, corrigé depuis.
/// « Un plafond plus court abandonne plus tôt, c'est le chemin qui ne touche à rien » : non, le
/// `tuer(pid:)` part AVANT la boucle d'attente, donc abandonner laisse une app TUÉE que rien ne
/// relance. Le plafond ne décide plus du sort de l'app, seulement de la patience du geste : la
/// surveillance se poursuit sans plafond dans `poursuivreFermeture`, et c'est `FermetureLenteTests`
/// qui en tient la preuve. Ce que les tests ci-dessous gardent, et qui reste vrai, c'est la
/// propriété N3 : le GESTE rend la main en moins d'une seconde, jamais en cinq.
@MainActor
struct AttenteDeMortTests {
    @Test("Une précédente qui ne meurt jamais est signalée en moins d'une seconde, pas en cinq")
    func refusDeQuitterNeVerrouillePlusLeGeste() async {
        let double = ControleurAppsDouble(lancees: [boring: 200], installees: [boring, vibe])
        double.sondagesAvantMort[boring] = .max   // la feuille « Enregistrer ? » attend l'utilisateur

        let debut = ContinuousClock.now
        let resultat = await basculeDeProduction(double).basculer(
            vers: info(vibe, .testing, pid: nil), depuis: info(boring, .unsupported, pid: 200)
        )
        let ecoule = ContinuousClock.now - debut

        #expect(resultat == .precedenteFermetureEnCours)
        #expect(ecoule < .seconds(2))              // 5 s avant le correctif
        // Et l'attente a bien eu lieu : le correctif borne le sondage, il ne le supprime pas.
        #expect(ecoule > .milliseconds(400))
        #expect(double.pid(pour: boring) == 200)   // jamais forcée : le travail de l'utilisateur est intact
        #expect(double.pid(pour: vibe) != nil)     // la cible, elle, est bien arrivée
    }

    @Test("Une cible qui refuse de mourir dans le repli de allumer laisse l'actuelle en place, vite")
    func repliAllumerAbandonneViteEtSansDegat() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100, boring: 200], installees: [vibe])
        double.sondagesAvantApparition[vibe] = .max // le démasquage ne ramène rien : repli
        double.sondagesAvantMort[vibe] = .max       // et la cible refuse de quitter

        let debut = ContinuousClock.now
        let resultat = await basculeDeProduction(double).basculer(
            vers: info(vibe, .supported, pid: 100), depuis: info(boring, .unsupported, pid: 200)
        )
        let ecoule = ContinuousClock.now - debut

        // « Pas encore fermée », et non « jamais apparue » : Bouncer a tué cette app, il ne peut
        // pas la déclarer perdue. `WindowManager` enchaîne sur la surveillance prolongée.
        #expect(resultat == .cibleFermetureEnCours)
        #expect(ecoule < .seconds(2))                        // 5 s avant le correctif
        #expect(double.journal.contains(.lance(vibe)) == false) // pas de relance sur un mourant
        #expect(double.pid(pour: boring) == 200)             // l'actuelle n'a pas été touchée
    }

    /// La non-régression qui compte : **le budget raccourci ne perd pas l'app**. Le process met
    /// trois sondages à mourir, comme un vrai ; la relance doit repartir sur un process NEUF.
    @Test("Une mort lente mais réelle relance toujours une instance neuve, aux durées du produit")
    func mortLenteNePerdPasLApp() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        double.sondagesAvantApparition[vibe] = 1  // la voie rapide échoue, le repli s'enclenche
        double.sondagesAvantMort[vibe] = 3        // et le process ne part pas sur-le-champ

        let resultat = await basculeDeProduction(double)
            .basculer(vers: info(vibe, .supported, pid: 100), depuis: nil)

        #expect(resultat == .reussie)
        let nouveau = double.pid(pour: vibe)
        #expect(nouveau != nil)
        #expect(nouveau != 100)                   // relancé APRÈS la mort, pas sur le mourant
        #expect(double.journal.contains(.tue(100)))
        #expect(double.journal.contains(.lance(vibe)))
    }

    /// L'autre moitié de la preuve : le plafond de la MORT a été raccourci, celui de l'APPARITION
    /// non. Une app froide qui met une seconde et demie à poser sa fenêtre réussit toujours — ce
    /// qu'un `delaiMax` ramené à 600 ms aurait cassé.
    @Test("Le délai d'apparition reste entier : une app lente à démarrer réussit encore")
    func delaiDApparitionNonRogne() async {
        let double = ControleurAppsDouble(lancees: [boring: 200], installees: [vibe])
        double.sondagesAvantApparition[vibe] = 30 // 30 sondages × 50 ms ≈ 1,5 s

        let debut = ContinuousClock.now
        let resultat = await basculeDeProduction(double).basculer(
            vers: info(vibe, .testing, pid: nil), depuis: info(boring, .unsupported, pid: 200)
        )
        let ecoule = ContinuousClock.now - debut

        #expect(resultat == .reussie)
        #expect(ecoule > .seconds(1))             // l'attente a bien duré : elle n'a pas été rognée
        #expect(double.sondagesAvantApparition[vibe] == 0)
    }
}
