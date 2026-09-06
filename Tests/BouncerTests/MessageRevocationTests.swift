//
// MessageRevocationTests.swift — Vérification de la véracité des messages liés à l'Accessibilité.
//
// Les messages affichés à l'utilisateur doivent décrire ce que le code fait RÉELLEMENT,
// sans promettre des comportements dégradés historiques qui n'existent plus :
// 1. Sans droit d'Accessibilité, Bouncer refuse les bascules nettes au lieu de quitter les apps.
// 2. Il ne promet pas qu'une bascule relancera les apps masquées tant que le droit manque.
// 3. Lors d'une révocation pendant la surveillance, il explique pourquoi l'encoche porte deux apps
//    et qu'un geste de plus n'y changera rien tant que le droit n'est pas rendu.
//

import Foundation
import Testing
@testable import BouncerCore

private let vibe = "app.vibeisland.macos"
private let boring = "theboringteam.boringnotch"

@MainActor
private final class DroitAX {
    var accorde = true
}

@MainActor
struct MessageRevocationTests {

    /// Lors d'une révocation globale sans apps masquées, le message ne doit plus prétendre
    /// que les bascules quitteront les apps. Il doit dire que les bascules ne fonctionnent plus,
    /// rassurer sur le fait qu'aucune app ne sera quittée, et indiquer comment réparer.
    @Test("Révocation générale sans apps masquées : le message dit la vérité et rassure")
    func revocationGeneraleSansAppsMasqueesDitLaVeriteEtReassure() async throws {
        let suite = "MessageRevocation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(lancees: [boring: 200, vibe: 100], installees: [boring, vibe])
        let ecran = EcranSimule()
        let droit = DroitAX()
        let wm = gestionnaire(
            double, ecran: ecran, suite: suite, defaults: defaults, dansLEncoche: [boring, vibe],
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                             delaiMax: .milliseconds(400), delaiMort: .milliseconds(5),
                             trustAccorde: { droit.accorde }, encocheMesurable: { ecran.branche }),
            verifierAccessibilite: { droit.accorde }
        )
        while wm.apps.contains(where: { $0.support == SupportStatus.testing }) { await Task.yield() }
        #expect(wm.bundleIDActive == boring)

        // Révocation du droit
        droit.accorde = false
        double.accessibiliteRevoquee = true
        wm.refreshTrustState()

        let message = try #require(wm.echecBascule)

        // Répond aux 3 questions dans l'ordre :
        // 1. Qu'est-ce qui ne marche plus
        #expect(message.contains("Accessibilité"))
        #expect(message.contains("les bascules ne fonctionnent plus"))
        // 2. Qu'est-ce que ça change pour mes apps ouvertes
        #expect(message.contains("Vos apps ouvertes restent intactes : Bouncer ne touche à rien et ne quittera aucune app."))
        // 3. Qu'est-ce que je fais pour réparer
        #expect(message.contains("Rendez-lui l'accès dans les Réglages Système pour réactiver les bascules."))

        // Contre-épreuve : le message NE DOIT PAS affirmer les anciens mensonges
        #expect(!message.contains("quitteront"))
        #expect(!message.contains("quitterait"))
        #expect(!message.contains("relancera"))

        // Preuve comportementale : une tentative de bascule ne quitte rien du tout
        await wm.basculer(vers: vibe)
        let appTuee = double.journal.contains { action in
            if case .tue = action { return true }
            return false
        }
        #expect(!appTuee)
        #expect(double.pid(pour: boring) == 200)
        #expect(double.fenetreVisibleDansNotch(pid: 200))
    }

    /// Lors d'une révocation avec des apps masquées en arrière-plan, le message ne doit pas promettre
    /// qu'une bascule va les relancer. Il constate qu'elles restent masquées sans que Bouncer ne les quitte.
    @Test("Révocation générale avec app masquée : ne promet pas une relance impossible")
    func revocationGeneraleAvecAppsMasqueesNePrometPasDeRelance() async throws {
        let suite = "MessageRevocationMasquee.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(lancees: [boring: 200, vibe: 100], installees: [boring, vibe])
        let ecran = EcranSimule()
        let droit = DroitAX()
        let wm = gestionnaire(
            double, ecran: ecran, suite: suite, defaults: defaults, dansLEncoche: [boring],
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                             delaiMax: .milliseconds(400), delaiMort: .milliseconds(5),
                             trustAccorde: { droit.accorde }, encocheMesurable: { ecran.branche }),
            verifierAccessibilite: { droit.accorde }
        )
        while wm.apps.contains(where: { $0.support == SupportStatus.testing }) { await Task.yield() }

        // On simule une app masquée par nos soins
        wm.injecterAppPourTest(NotchAppInfo(bundleID: vibe, name: vibe, support: .supported, pid: 100, isHiddenByUs: true))

        // Révocation
        droit.accorde = false
        double.accessibiliteRevoquee = true
        wm.refreshTrustState()

        let message = try #require(wm.echecBascule)

        #expect(message.contains("Accessibilité"))
        #expect(message.contains(vibe))
        #expect(message.contains("reste masquée en arrière-plan"))
        #expect(message.contains("Bouncer ne touche à rien et ne quittera aucune app."))
        #expect(message.contains("Réglages Système"))

        // Contre-épreuve : le message ne doit pas promettre une relance
        #expect(!message.contains("relancera"))
        #expect(!message.contains("quitteront"))

        // Preuve comportementale : tenter une bascule vers l'app masquée ne la relance pas
        await wm.basculer(vers: vibe)
        let appLancee = double.journal.contains { action in
            if case .lance = action { return true }
            return false
        }
        #expect(!appLancee)
    }

    /// Lorsque l'Accessibilité n'a jamais été accordée, une bascule refusée ne doit pas affirmer
    /// que basculer « quitterait » l'app. Elle doit affirmer que la bascule est refusée et que rien n'est touché.
    @Test("Bascule sans Accessibilité (.accessibiliteJamaisAccordee) : ne prétend pas qu'elle quitterait l'app")
    func basculeSansAccessibiliteNeDitPasQuElleQuitterait() async throws {
        let suite = "MessageBasculeRefusee.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(lancees: [boring: 200, vibe: 100], installees: [boring, vibe])
        let ecran = EcranSimule()
        let droit = DroitAX()
        droit.accorde = false
        let wm = gestionnaire(
            double, ecran: ecran, suite: suite, defaults: defaults, dansLEncoche: [boring, vibe],
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                             delaiMax: .milliseconds(400), delaiMort: .milliseconds(5),
                             trustAccorde: { droit.accorde }, encocheMesurable: { ecran.branche }),
            verifierAccessibilite: { droit.accorde }
        )

        await wm.basculer(vers: vibe)

        let message = try #require(wm.echecBascule)

        #expect(message.contains("Bouncer n'a pas encore l'accès à l'Accessibilité"))
        #expect(message.contains("la bascule vers \(vibe) est refusée"))
        #expect(message.contains("Bouncer ne touche à rien et ne quittera aucune app."))
        #expect(message.contains("Autorisez Bouncer dans les Réglages Système, puis réessayez."))

        // Contre-épreuve : ne contient pas le faux avertissement "quitterait"
        #expect(!message.contains("quitterait"))
        #expect(!message.contains("quitteront"))

        // Preuve comportementale : rien dans le journal, aucune action destructive
        #expect(double.journal.isEmpty)
        #expect(double.pid(pour: boring) == 200)
    }

    /// Révocation pendant la surveillance (.precedenteNonRangeableSansAccessibilite) :
    /// explique pourquoi l'utilisateur voit deux apps dans l'encoche et qu'un geste de plus n'y changera rien.
    @Test("Révocation pendant la surveillance : explique les deux apps et la sécurité des données")
    func revocationPendantSurveillanceExpliqueLesDeuxApps() async throws {
        let suite = "MessageRevocationSurveillance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(lancees: [boring: 200, vibe: 100], installees: [boring, vibe])
        let ecran = EcranSimule()
        let droit = DroitAX()
        let wm = gestionnaire(
            double, ecran: ecran, suite: suite, defaults: defaults, dansLEncoche: [boring, vibe],
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                             delaiMax: .milliseconds(400), delaiMort: .milliseconds(5),
                             trustAccorde: { droit.accorde }, encocheMesurable: { ecran.branche })
        )
        while wm.apps.contains(where: { $0.support == SupportStatus.testing }) { await Task.yield() }

        double.sondagesAvantApparition[vibe] = 1
        double.sondagesAvantMort[vibe] = 30
        double.resistantes = [boring]

        await wm.basculer(vers: vibe)
        let surveillance = wm.surveillanceFermeture
        #expect(surveillance != nil)

        droit.accorde = false
        double.accessibiliteRevoquee = true
        await surveillance?.value

        let message = try #require(wm.echecBascule)

        #expect(message.contains("Accessibilité"))
        #expect(message.contains(boring))
        #expect(message.contains("deux apps dans l'encoche"))
        #expect(message.contains("ne la quitte pas de force"))
        #expect(message.contains("aucun geste ne rangera l'encoche"))
        #expect(message.contains("Réglages Système"))

        #expect(!message.contains("quitteront"))
        #expect(!message.contains("relancera"))
    }
}
