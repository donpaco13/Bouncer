import Foundation
import Testing
@testable import BouncerCore

struct CatalogueTests {
    /// Un `UserDefaults` jetable et nettoyé pour la durée du test : sans ça les apprentissages
    /// fuiraient d'un test à l'autre — ils tournent en parallèle — et pollueraient les
    /// préférences réelles de la machine qui lance `swift test`. Une closure plutôt qu'un
    /// teardown : la portée est explicite et le suite reste une struct.
    private func avecDefaultsJetables(_ corps: (UserDefaults) throws -> Void) rethrows {
        let suite = "CatalogueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try corps(defaults)
    }

    private func url(_ nom: String) -> URL { URL(fileURLWithPath: "/Applications/\(nom).app") }

    /// Ce que les filtres précédents avaient appris a été appris à tort, et un apprentissage est
    /// définitif par construction : le changement de clé est la seule façon de le jeter.
    /// v1 → v2 jetait Finder, Discord, Arc, iScreen Shoter et Munder Difflin (filtre « la fenêtre
    /// effleure l'encoche »). v2 → v3 jette Bouncer elle-même, `UserNotificationCenter` et Handy
    /// (exclusion par pid, et fuite inter-écrans de `estFenetreEncoche`).
    @Test func lApprentissageDesAnciensFiltresEstJeteEtLeursClesEffacees() {
        avecDefaultsJetables { defaults in
            defaults.set(["com.apple.finder", "com.hnc.Discord"], forKey: "bouncer.bundleIDsApprises")
            defaults.set(
                ["io.github.donpaco13.bouncer", "com.apple.UserNotificationCenter", "com.pais.handy"],
                forKey: "bouncer.bundleIDsApprises.v2"
            )

            let catalogue = CatalogueApps(defaults: defaults, amorcage: [], resolveur: { url($0) })

            #expect(catalogue.apprises.isEmpty)
            #expect(defaults.stringArray(forKey: "bouncer.bundleIDsApprises") == nil)
            #expect(defaults.stringArray(forKey: "bouncer.bundleIDsApprises.v2") == nil)
        }
    }

    /// Le cœur de la task : le catalogue est une intersection avec le disque. Un bundleID
    /// d'amorçage qui ne correspond à rien d'installé ne doit pas apparaître.
    @Test func seulesLesAppsPresentesSurLeDisqueSontCataloguees() {
        avecDefaultsJetables { defaults in
            let catalogue = CatalogueApps(
                defaults: defaults,
                amorcage: ["app.installee", "app.absente"],
                resolveur: { $0 == "app.installee" ? url("Installée") : nil }
            )
            #expect(catalogue.installees().map(\.bundleID) == ["app.installee"])
        }
    }

    /// Une app apprise entre dans le catalogue sans être dans la liste d'amorçage — c'est ce qui
    /// permet à Bouncer de découvrir une app de notch dont on ignorait l'existence.
    @Test func uneAppApprisePersisteEtEntreDansLeCatalogue() {
        avecDefaultsJetables { defaults in
            let resolveur: CatalogueApps.Resolveur = { url($0 == "app.apprise" ? "Apprise" : "Amorcee") }

            let premiereSession = CatalogueApps(defaults: defaults, amorcage: [], resolveur: resolveur)
            #expect(premiereSession.installees().isEmpty)
            premiereSession.apprendre(bundleID: "app.apprise")

            // Une instance neuve sur le même stockage : c'est le vrai test de la persistance.
            let sessionSuivante = CatalogueApps(defaults: defaults, amorcage: [], resolveur: resolveur)
            #expect(sessionSuivante.installees().map(\.bundleID) == ["app.apprise"])
        }
    }

    /// Apprentissage et amorçage s'unissent, sans doublon quand une app est dans les deux.
    @Test func unionSansDoublonEntreApprisEtAmorcage() {
        avecDefaultsJetables { defaults in
            let catalogue = CatalogueApps(
                defaults: defaults, amorcage: ["app.a", "app.b"], resolveur: { url($0) }
            )
            catalogue.apprendre(bundleID: "app.b")
            catalogue.apprendre(bundleID: "app.b")
            catalogue.apprendre(bundleID: "app.c")
            #expect(catalogue.installees().map(\.bundleID) == ["app.a", "app.b", "app.c"])
        }
    }

    /// Le cycle swipe avance dans l'ordre du catalogue : cet ordre doit être le même à chaque
    /// lancement, sinon « l'app suivante » change de sens d'une session à l'autre.
    @Test func ordreStableEtIndependantDeLOrdreDApprentissage() {
        let resolveur: CatalogueApps.Resolveur = { id in
            url(["app.z": "Alpha", "app.a": "Zoulou"][id] ?? id)
        }
        avecDefaultsJetables { defaultsPremier in
            avecDefaultsJetables { defaultsSecond in
                let premier = CatalogueApps(defaults: defaultsPremier, amorcage: [], resolveur: resolveur)
                premier.apprendre(bundleID: "app.z")
                premier.apprendre(bundleID: "app.a")

                let second = CatalogueApps(defaults: defaultsSecond, amorcage: [], resolveur: resolveur)
                second.apprendre(bundleID: "app.a")
                second.apprendre(bundleID: "app.z")

                #expect(premier.installees().map(\.nom) == ["Alpha", "Zoulou"])
                #expect(premier.installees() == second.installees())
            }
        }
    }

    /// Une app désinstallée après avoir été apprise sort du catalogue, mais reste apprise :
    /// la réinstaller la fait revenir sans qu'on ait besoin de la revoir dans le notch.
    @Test func appDesinstalleeSortDuCatalogueMaisResteApprise() {
        avecDefaultsJetables { defaults in
            let catalogue = CatalogueApps(defaults: defaults, amorcage: [], resolveur: { _ in nil })
            catalogue.apprendre(bundleID: "app.desinstallee")
            #expect(catalogue.installees().isEmpty)

            let apresReinstallation = CatalogueApps(defaults: defaults, amorcage: [], resolveur: { url($0) })
            #expect(apresReinstallation.installees().map(\.bundleID) == ["app.desinstallee"])
        }
    }
}
