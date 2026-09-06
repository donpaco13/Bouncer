//
// FermetureLenteTests.swift — D2 et D3 de la QA passe 4 : une app tuée que Bouncer abandonnait.
//
// **Le défaut.** `fb1bdde` a ramené `delaiMort` de 5 s à 600 ms pour une bonne raison (N3 : une
// app qui refuse de quitter verrouillait le geste 5 s en silence) mais en gardant l'ABANDON au
// bout du plafond. Or `_ = controleur.tuer(pid:)` part AVANT la boucle d'attente : quand le
// plafond expire, l'app est DÉJÀ TUÉE et rien ne la relance. Son doc-comment affirmait
// qu'abandonner était « le chemin qui ne touche à rien » — c'était faux.
//
// **Ce que la QA a mesuré, et que ces tests rejouent.** Un bundle AppKit cobaye, entre
// `terminate()` et la disparition du pid : 53,6 à 87,6 ms à vide — le maximum dépasse déjà les
// 58,3 ms sur lesquels les 600 ms étaient calculées — et **867 à 894 ms dès que l'app a 800 ms de
// travail dans `applicationWillTerminate`, 0 sur 4 sous le plafond**. Une app d'encoche qui sauve
// son état en quittant est exactement ce cas. Le plafond n'a pas fermé l'enveloppe du défaut, il
// l'a rétrécie de 5 s à 0,6 s — donc rendue huit fois plus facile à atteindre.
//
// **L'horloge de ces tests.** Le double compte en SONDAGES, pas en millisecondes : un sondage de
// `pid(pour:)` rapproche un process mourant de sa fin. On sonde ici toutes les 10 ms, donc
// 1 sondage = 10 ms de temps simulé, et les deux durées mesurées par la QA se lisent directement :
// **62 sondages = 620 ms**, **89 sondages = 890 ms**. `delaiMort` garde sa valeur de production,
// 600 ms, ce qui place les deux morts hors de la fenêtre de courtoisie — et de façon
// DÉTERMINISTE : tenir 62 sondages en 600 ms demanderait 61 sommeils de 10 ms, soit 610 ms.
// La frontière ne peut donc pas basculer sur une lenteur de machine.
//
// **Ce que ces tests interdisent.** Remettre le plafond nu — abandonner au lieu de poursuivre la
// surveillance — les fait échouer tous les deux : la cible n'est jamais relancée, la précédente
// reste dans l'encoche à côté de la nouvelle.
//

import Foundation
import Testing
@testable import BouncerCore

private let vibe = "app.vibeisland.macos"
private let boring = "theboringteam.boringnotch"

private func info(_ bundleID: String, _ support: SupportStatus, pid: pid_t?) -> NotchAppInfo {
    NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
}

/// Les durées du produit, au sondage près : `delaiMort` = 600 ms et `delaiMax` = 5 s sont les
/// valeurs par défaut de `Bascule`. Seul l'intervalle de sondage est resserré à 10 ms, et il l'est
/// dans le sens conservateur — un sondage plus fin donne à la fenêtre de courtoisie PLUS d'occasions
/// de constater la mort. Si elle passe quand même la main ici, elle la passait aussi à 50 ms.
@MainActor
private func basculeDeProduction(_ double: ControleurAppsDouble) -> Bascule {
    Bascule(controleur: double, intervalleSondage: .milliseconds(10),
            trustAccorde: { true }, encocheMesurable: { true })
}

// MARK: - D2 : « Bouncer a tué, Bouncer relance » — quel que soit le temps que ça prend

@MainActor
struct FermetureLenteTests {

    /// Le cas exact de la QA, cible mourant en 620 ms. Avant le correctif : `.cibleJamaisApparue`,
    /// journal `[masque(false, 100), tue(100)]`, **pas de relance** — l'app de l'utilisateur reste
    /// morte pour de bon. C'est ça, perdre une app.
    @Test("Une cible qui met 620 ms à mourir est relancée, pas perdue")
    func cibleMourantEn620msNEstPasPerdue() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        // Le démasquage ne ramène rien à l'écran : la voie rapide échoue et le repli
        // tuer-puis-relancer s'enclenche. C'est le seul chemin où Bouncer tue la CIBLE.
        double.sondagesAvantApparition[vibe] = 1
        double.sondagesAvantMort[vibe] = 62        // 62 × 10 ms = 620 ms

        let bascule = basculeDeProduction(double)
        let cible = info(vibe, .supported, pid: 100)
        let premier = await bascule.basculer(vers: cible, depuis: nil)

        // Le geste rend la main vite — la propriété N3 est intacte — mais il ne DÉCLARE PAS
        // l'échec : il dit que la fermeture est en cours, et c'est ce verdict-là qui oblige
        // l'appelant à enchaîner. L'ancien code rendait ici `.cibleJamaisApparue`, un verdict
        // final sur une app qu'il venait de tuer.
        #expect(premier == .cibleFermetureEnCours)
        #expect(double.journal.contains(.tue(100)))
        #expect(double.journal.contains(.lance(vibe)) == false) // rien ne se relance sur un mourant

        // La suite, sans plafond : on a tué, on constate la mort, et on relance.
        let final = await bascule.poursuivreFermeture(de: cible, puisRelancer: true)

        #expect(final == .reussie)
        #expect(double.journal.contains(.lance(vibe)))
        let nouveau = double.pid(pour: vibe)
        #expect(nouveau != nil)        // LA propriété : l'app de l'utilisateur est toujours là
        #expect(nouveau != 100)        // et c'est une instance neuve, pas le mourant relancé
    }

    /// La seconde conséquence, tout aussi grave : une PRÉCÉDENTE qui met 890 ms à mourir laissait
    /// **deux apps dans l'encoche**, le problème que Bouncer existe pour résoudre. À 5 s ce cas
    /// réussissait ; à 600 ms nus, non.
    @Test("Une précédente qui met 890 ms à mourir libère bien l'encoche")
    func precedenteMourantEn890msLibereLEncoche() async {
        let double = ControleurAppsDouble(lancees: [boring: 200], installees: [boring, vibe])
        double.resistantes = [boring]              // pas masquable : la seule sortie est de la quitter
        double.sondagesAvantMort[boring] = 89      // 89 × 10 ms = 890 ms

        let bascule = basculeDeProduction(double)
        let precedente = info(boring, .unsupported, pid: 200)
        let premier = await bascule.basculer(vers: info(vibe, .testing, pid: nil), depuis: precedente)

        // L'état que la QA a photographié : la cible est arrivée, la précédente est encore là.
        #expect(premier == .precedenteFermetureEnCours)
        #expect(double.pid(pour: vibe) != nil)
        #expect(double.pid(pour: boring) == 200)

        let final = await bascule.poursuivreFermeture(de: precedente, puisRelancer: false)

        #expect(final == .reussie)
        #expect(double.pid(pour: boring) == nil)   // l'encoche n'en porte plus qu'une
        #expect(double.pid(pour: vibe) != nil)
    }

    /// La surveillance est sans plafond, donc sa seule sortie est l'annulation — et elle
    /// appartient au geste suivant de l'utilisateur. Sans ce garde, `poursuivreFermeture`
    /// relancerait une app que l'utilisateur vient d'abandonner pour une autre, et l'encoche en
    /// porterait deux : on aurait troqué la perte d'app contre le doublon.
    @Test("Un geste suivant annule la surveillance : pas de relance dans le dos de l'utilisateur")
    func surveillanceAnnuleeNeRelancePas() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        double.sondagesAvantMort[vibe] = .max      // elle ne meurt jamais : la boucle tournerait sans fin
        _ = double.tuer(pid: 100)

        let bascule = basculeDeProduction(double)
        let tache = Task { await bascule.poursuivreFermeture(de: info(vibe, .supported, pid: 100),
                                                             puisRelancer: true) }
        // Le temps que la boucle prenne quelques tours, puis le geste suivant.
        try? await Task.sleep(for: .milliseconds(50))
        tache.cancel()

        #expect(await tache.value == .cibleFermetureEnCours)   // « toujours en cours », pas « réussie »
        #expect(double.journal.contains(.lance(vibe)) == false)
    }

    /// Le cas de tous les jours ne doit rien payer de tout ça : 53 à 88 ms mesurés, très en deçà
    /// des 600 ms de courtoisie. La bascule rend `.reussie` du premier coup, sans surveillance.
    @Test("Une mort normale reste un succès franc dans la fenêtre de courtoisie")
    func mortNormaleResteUnSuccesImmediat() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        double.sondagesAvantApparition[vibe] = 1
        double.sondagesAvantMort[vibe] = 8         // 8 × 10 ms = 80 ms, le haut de la mesure à vide

        let resultat = await basculeDeProduction(double)
            .basculer(vers: info(vibe, .supported, pid: 100), depuis: nil)

        #expect(resultat == .reussie)
        #expect(double.pid(pour: vibe) != 100)
    }
}

// MARK: - D3 : le refus d'un second geste n'est plus muet

/// **Le défaut.** Sur une app qui traîne à quitter, chaque geste déclenche un `terminate()` de plus
/// et le garde de `WindowManager.basculer` reste MUET : l'utilisateur swipe, rien ne bouge, il
/// resswipe, rien ne bouge. `fb1bdde` a réglé la DURÉE (0,62 s contre 5,01 s), pas le silence.
///
/// Le correctif tient en deux surfaces, et aucune ne demande d'ouvrir quoi que ce soit : l'icône
/// de la barre des menus passe au sablier pendant la bascule (`App.swift`), et un second geste
/// pose un message qui l'explique.
@MainActor
struct GesteRefuseParleTests {

    @Test("Un second geste pendant une bascule reçoit un message, pas un silence")
    func secondGestePendantUneBasculeEstExplique() async {
        let suite = "FermetureLenteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(installees: [vibe])
        // L'app se lance mais ne dessine jamais rien dans l'encoche : la bascule tient le temps de
        // son `delaiMax`, qu'on raccourcit ici — c'est la fenêtre pendant laquelle on resswipe.
        double.sondagesAvantApparition[vibe] = .max

        let wm = WindowManager(
            startTimer: false,
            catalogue: CatalogueApps(defaults: defaults, amorcage: [vibe],
                                     resolveur: { _ in URL(fileURLWithPath: "/Applications/VibeIsland.app") }),
            controleur: double,
            reglages: Reglages(defaults: defaults),
            geometrie: { nil },
            demanderAccessibilite: false,
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(5),
                             delaiMax: .milliseconds(300), delaiMort: .milliseconds(300),
                             trustAccorde: { true }, encocheMesurable: { true })
        )

        let premier = Task { await wm.basculer(vers: vibe) }
        // Laisser le premier geste prendre le verrou, puis en tenter un second.
        while wm.bundleIDEnCoursDeBascule == nil { await Task.yield() }
        await wm.basculer(vers: vibe)

        // Le second geste a été refusé — c'est voulu — mais il a laissé une trace à l'écran.
        // Avant le correctif : `return` sec, et l'icône de la barre des menus inchangée.
        #expect(wm.echecBascule != nil)
        _ = await premier.value
    }
}
