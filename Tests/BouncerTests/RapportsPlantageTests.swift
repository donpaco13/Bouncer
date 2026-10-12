//
// RapportsPlantageTests.swift — Sentry est opt-in : rien ne démarre tant que l'utilisateur n'a
// rien coché. C'est la promesse de docs/CONFIDENTIALITE.md, et ce test la tient.
//

import Foundation
import Testing
@testable import BouncerCore

struct RapportsPlantageTests {
    private func defaultsJetables(_ nom: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: nom)!
        d.removePersistentDomain(forName: nom)
        return d
    }

    @Test("Avec le réglage par défaut, Sentry ne démarre pas")
    func coupeParDefaut() {
        let reglages = Reglages(defaults: defaultsJetables(), appliquerLangue: { _ in })
        var demarrages = 0, arrets = 0
        let pilote = PiloteRapportsPlantage(reglages: reglages,
                                            demarrer: { demarrages += 1 }, arreter: { arrets += 1 })
        #expect(reglages.rapportsPlantage == false)
        #expect(demarrages == 0)
        #expect(arrets == 0)
        withExtendedLifetime(pilote) {}
    }

    @Test("Cocher démarre une fois, décocher arrête, et le choix survit à la relance")
    func cocherPuisDecocher() {
        let defaults = defaultsJetables()
        let reglages = Reglages(defaults: defaults, appliquerLangue: { _ in })
        var journal: [String] = []
        let pilote = PiloteRapportsPlantage(reglages: reglages,
                                            demarrer: { journal.append("start") },
                                            arreter: { journal.append("close") })
        reglages.rapportsPlantage = true
        reglages.rapportsPlantage = true
        #expect(journal == ["start"])
        #expect(Reglages(defaults: defaults, appliquerLangue: { _ in }).rapportsPlantage)

        reglages.rapportsPlantage = false
        #expect(journal == ["start", "close"])
        #expect(Reglages(defaults: defaults, appliquerLangue: { _ in }).rapportsPlantage == false)
        withExtendedLifetime(pilote) {}
    }
}
