//
// CadenceTests.swift — l'échelle de ralentissement du sondage.
//
// Le sondage ne peut pas être remplacé par des notifications : `NSWorkspace.didLaunchApplication`
// dit qu'un process a démarré, jamais que sa fenêtre d'encoche est à l'écran, et c'est
// précisément cet écart que le scan mesure. Il est donc ESPACÉ quand rien ne bouge, et les
// notifications servent de réveil. Ce qui se vérifie ici, c'est le compromis : assez rapide
// juste après un mouvement, assez lent une fois la machine posée, jamais lent au point de
// rendre l'app molle.

import Testing
import Foundation
@testable import BouncerCore

@Suite("Cadence adaptative du sondage")
struct CadenceTests {
    private let base: TimeInterval = 2

    @Test("Après un réveil, la cadence reste pleine le temps que l'utilisateur agisse")
    func cadencePleineJusteApresUnReveil() {
        for tours in 0...3 {
            #expect(
                WindowManager.periodeDeRepos(base: base, toursImmobiles: tours, accessibiliteAccordee: true) == base,
                "un mouvement récent ne doit jamais coûter d'attente"
            )
        }
    }

    @Test("Rien ne bouge : la période double par cran et se plafonne")
    func ralentissementProgressifEtPlafonne() {
        let periodes = (4...12).map {
            WindowManager.periodeDeRepos(base: base, toursImmobiles: $0, accessibiliteAccordee: true)
        }
        #expect(periodes.prefix(4) == [4, 8, 16, 30])
        #expect(periodes.allSatisfy { $0 <= 30 }, "au-delà de 30 s, un changement non notifié dormirait trop longtemps")
        #expect(zip(periodes, periodes.dropFirst()).allSatisfy { $0 <= $1 }, "la cadence ne doit jamais réaccélérer toute seule")
    }

    @Test("Sans droits d'Accessibilité, on ne ralentit jamais")
    func jamaisDeRalentissementPendantLOnboarding() {
        // Aucune notification ne dit que l'utilisateur vient de cocher Bouncer dans les Réglages
        // Système : ce timer est la seule chose qui fait avancer l'accueil sous ses yeux.
        for tours in [0, 5, 50, 5000] {
            #expect(WindowManager.periodeDeRepos(base: base, toursImmobiles: tours, accessibiliteAccordee: false) == base)
        }
    }

    @Test("Le plafond de repos vaut pour toutes les périodes réglables")
    func plafondValableSurTouteLaPlageDeReglage() {
        for socle in Reglages.Domaine.intervalles {
            let repos = WindowManager.periodeDeRepos(base: socle, toursImmobiles: 99, accessibiliteAccordee: true)
            #expect(repos <= 30)
            #expect(repos >= socle, "ralentir ne doit jamais rendre le sondage plus rapide que ce qui est réglé")
        }
    }
}
