//
// ReglagesTests.swift — verrouille les trois endroits où les préférences peuvent mentir.
//
// Un `UserDefaults(suiteName:)` jetable par test : sans ça, la suite écrirait dans les
// préférences réelles de la machine qui la lance, et un test raté laisserait Bouncer déréglé.
//

import Foundation
import Testing
@testable import BouncerCore

struct ReglagesTests {
    /// Un domaine de préférences vide, propre à chaque test.
    private func defaultsJetables(_ nom: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: nom)!
        d.removePersistentDomain(forName: nom)
        return d
    }

    @Test("Sans rien d'enregistré, les défauts sont ceux qui étaient en dur dans le code")
    func defautsDOrigine() {
        let r = Reglages(defaults: defaultsJetables())
        #expect(r.modeActivation == .lesDeux)
        #expect(r.porteeApproche == 72)
        #expect(r.margeLaterale == 44)
        #expect(r.intervalleRafraichissement == 2)
        #expect(r.bundleIDsExclus.isEmpty)
    }

    @Test("Une portée de 0 est une valeur légale, pas une clé absente")
    func porteeZeroSurvitAuRechargement() {
        // Le piège que ce test verrouille : `defaults.double(forKey:)` rend 0 pour une clé
        // ABSENTE. Lire la portée avec lui rendrait donc « pas de rampe » indistinguable de
        // « jamais réglé », et un premier lancement livrerait des flèches sans approche.
        let defaults = defaultsJetables()
        let r = Reglages(defaults: defaults)
        r.porteeApproche = 0
        #expect(Reglages(defaults: defaults).porteeApproche == 0)
    }

    @Test("Une valeur hors domaine est ramenée dans le domaine, jamais appliquée telle quelle")
    func bornage() {
        let defaults = defaultsJetables()
        // Écrite à la main dans les préférences (`defaults write`), donc jamais passée par le
        // curseur qui la bornerait.
        defaults.set(9999.0, forKey: "bouncer.porteeApproche")
        defaults.set(-5.0, forKey: "bouncer.margeLaterale")
        defaults.set(3.7, forKey: "bouncer.intervalleRafraichissement")

        let r = Reglages(defaults: defaults)
        #expect(r.porteeApproche == Reglages.Domaine.portee.upperBound)
        #expect(r.margeLaterale == Reglages.Domaine.marge.lowerBound)
        // 3,7 s n'est pas une des périodes proposées : on retombe sur le défaut plutôt que de
        // planifier un timer sur une valeur que l'interface ne saurait pas afficher.
        #expect(r.intervalleRafraichissement == Reglages.Domaine.intervalleDefaut)
    }

    @Test("Écrire une valeur hors domaine par la propriété la borne — et ne boucle pas")
    func bornageParLaPropriete() {
        // Ce test aurait attrapé un crash en réel (EXC_BAD_ACCESS, débordement de pile) : la
        // version d'avant bornait dans le `didSet` d'un `@Published` en se réassignant, or
        // `@Published` est un property wrapper — la propriété est CALCULÉE, donc la
        // réassignation repasse par le setter et `didSet` se rappelle sans fin. Bouger le
        // curseur de la fenêtre de réglages tuait l'app. S'il revient, ce test n'échoue pas :
        // il plante, ce qui se voit encore mieux.
        let defaults = defaultsJetables()
        let r = Reglages(defaults: defaults)

        r.porteeApproche = 5_000
        r.margeLaterale = -100
        r.intervalleRafraichissement = 3.7

        #expect(r.porteeApproche == Reglages.Domaine.portee.upperBound)
        #expect(r.margeLaterale == Reglages.Domaine.marge.lowerBound)
        // Une période hors liste est refusée, pas rabotée : il n'y a pas de « plus proche » qui
        // veuille dire quelque chose entre 2 s et 5 s.
        #expect(r.intervalleRafraichissement == Reglages.Domaine.intervalleDefaut)

        // Et ce qui a été borné est bien ce qui se relit.
        #expect(Reglages(defaults: defaults).porteeApproche == Reglages.Domaine.portee.upperBound)
        #expect(Reglages(defaults: defaults).margeLaterale == Reglages.Domaine.marge.lowerBound)
    }

    @Test("Rétablir les valeurs d'origine ne jette pas la liste d'exclusions")
    func reinitialisationGardeLesExclusions() {
        let r = Reglages(defaults: defaultsJetables())
        r.porteeApproche = 10
        r.exclusion("app.vibeisland.macos", exclue: true)

        r.reinitialiser()

        #expect(r.porteeApproche == 72)
        // Les exclusions ne sont pas un réglage de sensation : elles ont été composées app par
        // app, et un bouton « valeurs d'origine » qui les efface est une surprise coûteuse.
        #expect(r.bundleIDsExclus == ["app.vibeisland.macos"])
    }

    @Test("Une exclusion survit au rechargement")
    func exclusionPersistee() {
        let defaults = defaultsJetables()
        let r = Reglages(defaults: defaults)
        r.exclusion("theboringteam.boringnotch", exclue: true)
        #expect(Reglages(defaults: defaults).bundleIDsExclus == ["theboringteam.boringnotch"])

        r.exclusion("theboringteam.boringnotch", exclue: false)
        #expect(Reglages(defaults: defaults).bundleIDsExclus.isEmpty)
    }

    @Test("Le mode d'activation dit ce que chaque entrée du geste a le droit de faire")
    func modeActivation() {
        #expect(ModeActivation.lesDeux.swipeActif && ModeActivation.lesDeux.flechesActives)
        #expect(ModeActivation.swipeSeul.swipeActif && !ModeActivation.swipeSeul.flechesActives)
        #expect(!ModeActivation.flechesSeules.swipeActif && ModeActivation.flechesSeules.flechesActives)
    }
}

struct CyclablesTests {
    private func entree(_ id: String) -> EntreeMenu {
        EntreeMenu(bundleID: id, nom: id, etat: .inactive, detail: "")
    }

    @Test("Le cycle saute les apps exclues, et garde l'ordre du menu")
    func exclusionRetireDuCycle() {
        let entrees = [entree("a"), entree("b"), entree("c")]
        #expect(bundleIDsCyclables(entrees: entrees, exclus: ["b"]) == ["a", "c"])
    }

    @Test("Tout exclure rend le geste inerte plutôt que de le faire boucler sur rien")
    func toutExclu() {
        let entrees = [entree("a"), entree("b")]
        let cyclables = bundleIDsCyclables(entrees: entrees, exclus: ["a", "b"])
        #expect(cyclables.isEmpty)
        // C'est la garantie qui compte : `cycle()` s'appuie dessus pour être un no-op au lieu de
        // planter ou de rebasculer sur l'app en cours.
        #expect(prochaineCible(dans: cyclables, depuis: nil, forward: true) == nil)
    }

    @Test("Une exclusion inconnue du menu ne retire rien")
    func exclusionObsolete() {
        // Une app désinstallée reste dans la liste d'exclusions (on ne purge pas : la réinstaller
        // doit retrouver le choix). Elle ne doit rien casser au cycle en attendant.
        let entrees = [entree("a")]
        #expect(bundleIDsCyclables(entrees: entrees, exclus: ["disparue"]) == ["a"])
    }
}
