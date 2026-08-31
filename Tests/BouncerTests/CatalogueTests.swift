import XCTest
@testable import BouncerCore

final class CatalogueTests: XCTestCase {
    /// Un `UserDefaults` jetable par test : sans ça les apprentissages d'un test fuiraient
    /// dans le suivant, et dans les préférences réelles de la machine qui lance `swift test`.
    private func defaultsJetables(_ nom: String = #function) -> UserDefaults {
        let suite = "CatalogueTests.\(nom).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        return d
    }

    private func url(_ nom: String) -> URL { URL(fileURLWithPath: "/Applications/\(nom).app") }

    /// Le cœur de la task : le catalogue est une intersection avec le disque. Un bundleID
    /// d'amorçage qui ne correspond à rien d'installé ne doit pas apparaître.
    func testSeulesLesAppsPresentesSurLeDisqueSontCataloguees() {
        let catalogue = CatalogueApps(
            defaults: defaultsJetables(),
            amorcage: ["app.installee", "app.absente"],
            resolveur: { $0 == "app.installee" ? self.url("Installée") : nil }
        )
        XCTAssertEqual(catalogue.installees().map(\.bundleID), ["app.installee"])
    }

    /// Une app apprise entre dans le catalogue sans être dans la liste d'amorçage — c'est ce qui
    /// permet à Bouncer de découvrir une app de notch dont on ignorait l'existence.
    func testUneAppApprisePersisteEtEntreDansLeCatalogue() {
        let defaults = defaultsJetables()
        let resolveur: CatalogueApps.Resolveur = { self.url($0 == "app.apprise" ? "Apprise" : "Amorcee") }

        let premiereSession = CatalogueApps(defaults: defaults, amorcage: [], resolveur: resolveur)
        XCTAssertTrue(premiereSession.installees().isEmpty)
        premiereSession.apprendre(bundleID: "app.apprise")

        // Une instance neuve sur le même stockage : c'est le vrai test de la persistance.
        let sessionSuivante = CatalogueApps(defaults: defaults, amorcage: [], resolveur: resolveur)
        XCTAssertEqual(sessionSuivante.installees().map(\.bundleID), ["app.apprise"])
    }

    /// Apprentissage et amorçage s'unissent, sans doublon quand une app est dans les deux.
    func testUnionSansDoublonEntreApprisEtAmorcage() {
        let catalogue = CatalogueApps(
            defaults: defaultsJetables(),
            amorcage: ["app.a", "app.b"],
            resolveur: { self.url($0) }
        )
        catalogue.apprendre(bundleID: "app.b")
        catalogue.apprendre(bundleID: "app.b")
        catalogue.apprendre(bundleID: "app.c")
        XCTAssertEqual(catalogue.installees().map(\.bundleID), ["app.a", "app.b", "app.c"])
    }

    /// Le cycle swipe avance dans l'ordre du catalogue : cet ordre doit être le même à chaque
    /// lancement, sinon "l'app suivante" change de sens d'une session à l'autre.
    func testOrdreStableEtIndependantDeLOrdreDApprentissage() {
        let resolveur: CatalogueApps.Resolveur = { id in
            self.url(["app.z": "Alpha", "app.a": "Zoulou"][id] ?? id)
        }
        let premier = CatalogueApps(defaults: defaultsJetables(), amorcage: [], resolveur: resolveur)
        premier.apprendre(bundleID: "app.z")
        premier.apprendre(bundleID: "app.a")

        let second = CatalogueApps(defaults: defaultsJetables(), amorcage: [], resolveur: resolveur)
        second.apprendre(bundleID: "app.a")
        second.apprendre(bundleID: "app.z")

        XCTAssertEqual(premier.installees().map(\.nom), ["Alpha", "Zoulou"])
        XCTAssertEqual(premier.installees(), second.installees())
    }

    /// Une app désinstallée après avoir été apprise sort du catalogue, mais reste apprise :
    /// la réinstaller la fait revenir sans qu'on ait besoin de la revoir dans le notch.
    func testAppDesinstalleeSortDuCatalogueMaisResteApprise() {
        let defaults = defaultsJetables()
        let catalogue = CatalogueApps(defaults: defaults, amorcage: [], resolveur: { _ in nil })
        catalogue.apprendre(bundleID: "app.desinstallee")
        XCTAssertTrue(catalogue.installees().isEmpty)

        let apresReinstallation = CatalogueApps(defaults: defaults, amorcage: [], resolveur: { self.url($0) })
        XCTAssertEqual(apresReinstallation.installees().map(\.bundleID), ["app.desinstallee"])
    }
}
