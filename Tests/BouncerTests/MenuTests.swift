//
// MenuTests.swift — la construction des lignes du menu, sans WindowManager ni vraie app.
//
// Swift Testing, comme CatalogueTests et BasculeTests.
//

import Foundation
import Testing
@testable import BouncerCore

struct MenuTests {
    private func app(
        _ bundleID: String, _ nom: String,
        support: SupportStatus = .supported, pid: pid_t? = 1234, masquee: Bool = false
    ) -> NotchAppInfo {
        NotchAppInfo(bundleID: bundleID, name: nom, support: support, pid: pid, isHiddenByUs: masquee)
    }

    private func installee(_ bundleID: String, _ nom: String) -> AppInstallee {
        AppInstallee(bundleID: bundleID, nom: nom, url: URL(fileURLWithPath: "/Applications/\(nom).app"))
    }

    /// Le point de tout le chantier : une app résistante est une ligne comme les autres. Le verdict
    /// ne survit que comme détail secondaire, et il n'y a plus rien pour la griser.
    @Test func uneAppResistanteEstUneLigneCommeLesAutres() {
        let entrees = construireEntreesMenu(
            apps: [app("a.vibe", "Vibe Island"), app("b.boring", "boringNotch", support: .unsupported)],
            installees: [],
            active: "a.vibe",
            enCoursDeBascule: nil
        )
        #expect(entrees.map(\.bundleID) == ["b.boring", "a.vibe"])  // trié par nom
        #expect(entrees[0].etat == .inactive)
        #expect(entrees[1].etat == .active)
        // Le libellé principal ne porte que le nom : le verdict est ailleurs.
        #expect(entrees[0].nom == "boringNotch")
        #expect(entrees[0].detail == SupportStatus.unsupported.consequencePourUtilisateur)
        #expect(!entrees[0].detail.contains(SupportStatus.unsupported.rawValue))
    }

    /// Une app du catalogue qui ne tourne pas doit être listée : c'est elle qu'on relancera.
    @Test func uneAppArreteeDuCatalogueEstListee() {
        let entrees = construireEntreesMenu(
            apps: [app("a.vibe", "Vibe Island")],
            installees: [installee("a.vibe", "Vibe Island"), installee("z.notchy", "Notchy")],
            active: "a.vibe",
            enCoursDeBascule: nil
        )
        #expect(entrees.map(\.bundleID) == ["z.notchy", "a.vibe"])
        #expect(entrees[0].detail == "Arrêtée — sera relancée")
        // Pas de doublon quand le catalogue et la découverte parlent de la même app.
        #expect(entrees.count == 2)
    }

    /// L'app détectée mais dont le process est mort garde sa ligne, sans son verdict : ce qui
    /// compte pour l'utilisateur est qu'elle sera relancée, pas comment elle se masquait.
    @Test func uneAppDetecteeSansPidAnnonceSaRelance() {
        let entrees = construireEntreesMenu(
            apps: [app("a.vibe", "Vibe Island", pid: nil)],
            installees: [], active: nil, enCoursDeBascule: nil
        )
        #expect(entrees[0].detail == "Arrêtée — sera relancée")
    }

    /// L'état « en cours » prime sur tout le reste, y compris sur l'app active : c'est lui qui
    /// empêche le second clic.
    @Test func lEtatEnCoursPrimeSurLActive() {
        let entrees = construireEntreesMenu(
            apps: [app("a.vibe", "Vibe Island"), app("b.boring", "boringNotch")],
            installees: [],
            active: "a.vibe",
            enCoursDeBascule: "a.vibe"
        )
        #expect(entrees.first(where: { $0.bundleID == "a.vibe" })?.etat == .enCours)
        #expect(entrees.first(where: { $0.bundleID == "b.boring" })?.etat == .inactive)
    }

    /// Aucune app active : aucune marque, et surtout aucun plantage.
    @Test func sansAppActiveAucuneEntreeNEstMarquee() {
        let entrees = construireEntreesMenu(
            apps: [app("a.vibe", "Vibe Island")], installees: [], active: nil, enCoursDeBascule: nil
        )
        #expect(entrees.allSatisfy { $0.etat == .inactive })
    }
}
