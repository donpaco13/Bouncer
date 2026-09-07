//
// RelanceTests.swift — vérification de la relance et de sa localisation.
//

import Foundation
import Testing
@testable import BouncerCore

@Suite("Relance de Bouncer")
@MainActor
struct RelanceTests {

    // MARK: - Localisation

    @Test("La clé existe dans les catalogues français et anglais avec le bon libellé")
    func clesLocalisationExistent() throws {
        let fr = texte("settings.general.relaunch")
        #expect(fr != "settings.general.relaunch", "La clé doit être traduite")

        let bundleEn = try #require(
            catalogueDeChaines.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let cheminEn = try #require(bundleEn.path(forResource: "Localizable", ofType: "strings"))
        let tableEn = try #require(NSDictionary(contentsOfFile: cheminEn) as? [String: String])
        #expect(tableEn["settings.general.relaunch"] == "Relaunch Bouncer")

        let bundleFr = try #require(
            catalogueDeChaines.path(forResource: "fr", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let cheminFr = try #require(bundleFr.path(forResource: "Localizable", ofType: "strings"))
        let tableFr = try #require(NSDictionary(contentsOfFile: cheminFr) as? [String: String])
        #expect(tableFr["settings.general.relaunch"] == "Relancer Bouncer")
    }

    // MARK: - Commande de relance

    @Test("La commande pour un bundle .app utilise /bin/sh avec attente de mort et /usr/bin/open")
    func commandeRelancePourBundleApp() {
        let fakePID: pid_t = 4242
        let bundleURL = URL(fileURLWithPath: "/Applications/Bouncer.app")
        let commande = RelanceurApp.commandeRelance(pid: fakePID, bundleURL: bundleURL)

        #expect(commande.executable.path == "/bin/sh")
        #expect(commande.arguments.count == 5)
        #expect(commande.arguments[0] == "-c")
        #expect(commande.arguments[1] == "while /bin/kill -0 $1 2>/dev/null; do /bin/sleep 0.05; done; /usr/bin/open \"$2\"")
        #expect(commande.arguments[2] == "_")
        #expect(commande.arguments[3] == "4242")
        #expect(commande.arguments[4] == "/Applications/Bouncer.app")
    }

    @Test("La commande pour un exécutable brut (hors .app) lance le binaire directement")
    func commandeRelancePourBinaireBrut() {
        let fakePID: pid_t = 1001
        let binaryURL = URL(fileURLWithPath: "/Users/dev/.build/release/Bouncer")
        let commande = RelanceurApp.commandeRelance(pid: fakePID, bundleURL: binaryURL)

        #expect(commande.executable.path == "/bin/sh")
        #expect(commande.arguments[1] == "while /bin/kill -0 $1 2>/dev/null; do /bin/sleep 0.05; done; \"$2\"")
        #expect(commande.arguments[3] == "1001")
        #expect(commande.arguments[4] == "/Users/dev/.build/release/Bouncer")
    }

    // MARK: - Appel de la fonction de relance

    @Test("relancer() exécute le helper et ordonne la terminaison de l'application")
    func relancerDeclencheExecutionEtTerminaison() {
        var commandeExecutee: (executable: URL, arguments: [String])?
        var appTerminee = false

        let fakePID: pid_t = 9876
        let fakeURL = URL(fileURLWithPath: "/Applications/Bouncer.app")

        let relanceur = RelanceurApp(
            obtenirPID: { fakePID },
            obtenirBundleURL: { fakeURL },
            executeProcessus: { executable, arguments in
                commandeExecutee = (executable, arguments)
            },
            terminerApp: {
                appTerminee = true
            }
        )

        let succes = relanceur.relancer()

        #expect(succes == true)
        #expect(commandeExecutee != nil)
        #expect(commandeExecutee?.executable.path == "/bin/sh")
        #expect(commandeExecutee?.arguments.contains("/Applications/Bouncer.app") == true)
        #expect(appTerminee == true)
    }

    @Test("relancer() n'arrête pas l'application si le helper échoue à démarrer")
    func relancerEchecHelperNeTuePasApp() {
        var appTerminee = false

        struct ErreurLancementHelper: Error {}

        let relanceur = RelanceurApp(
            obtenirPID: { 1234 },
            obtenirBundleURL: { URL(fileURLWithPath: "/Applications/Bouncer.app") },
            executeProcessus: { _, _ in
                throw ErreurLancementHelper()
            },
            terminerApp: {
                appTerminee = true
            }
        )

        let succes = relanceur.relancer()

        #expect(succes == false)
        #expect(appTerminee == false, "L'app ne doit pas quitter si le sous-processus de relance n'a pas pu démarrer")
    }
}
