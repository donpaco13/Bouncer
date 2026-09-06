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
        #expect(periodes.prefix(3) == [4, 8, 8])
        #expect(periodes.allSatisfy { $0 <= 8 }, "au-delà de 8 s, la géométrie de l'encoche aurait trop de retard")
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
            #expect(repos <= max(socle, 8))
            #expect(repos >= socle, "ralentir ne doit jamais rendre le sondage plus rapide que ce qui est réglé")
        }
    }

    @Test("Le réveil ne se déclenche pas sur une simple traversée")
    @MainActor
    func simpleTraverseeNeReveillePas() async throws {
        let suite = "CadenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let wm = WindowManager(
            startTimer: false,
            catalogue: CatalogueApps(defaults: defaults, resolveur: { _ in nil }),
            controleur: ControleurAppsDouble(),
            reglages: Reglages(defaults: defaults),
            geometrie: { nil },
            demanderAccessibilite: false,
            notificationCenter: NotificationCenter()
        )
        wm.delaiArretCurseur = 0.05
        wm.definirToursImmobilesPourTest(5)
        #expect(wm.toursImmobiles == 5)

        // Traversée rapide : le curseur entre puis sort immédiatement
        wm.curseurDansZone(true)
        wm.curseurDansZone(false)

        // Attendre que le délai soit écoulé
        try await Task.sleep(for: .milliseconds(80))
        #expect(wm.toursImmobiles == 5, "une simple traversée ne doit pas casser la cadence de repos")

        // En revanche, un curseur qui s'arrête dans la zone doit réveiller
        wm.curseurDansZone(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(wm.toursImmobiles == 1, "un curseur qui s'arrête dans la zone doit réveiller le sondage")
    }
}
