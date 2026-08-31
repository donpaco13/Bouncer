//
// BasculeTests.swift — le double de `ControleurApps`, et la preuve qu'il se comporte comme
// le vrai système sur les points dont la machine à états dépendra.
//
// Écrit avec Swift Testing (pas XCTest comme CycleTests/ModeleTests) : les deux frameworks
// cohabitent dans la même cible sans rien changer à `Package.swift`.
//

import Foundation
import Testing
@testable import BouncerCore

/// Ce que le double a vu passer, dans l'ordre — c'est ce journal qui permettra de tester
/// « la précédente n'est tuée qu'après l'apparition de la suivante ».
enum ActionControleur: Equatable {
    case lance(String)
    case tue(pid_t)
    case masque(Bool, pid_t)
}

/// Le double du protocole. Il simule ce qui compte pour la bascule et rien d'autre : quelles apps
/// tournent, laquelle est masquée, et au bout de combien de sondages la fenêtre d'une app
/// fraîchement lancée apparaît dans l'encoche.
///
/// `@MainActor` comme le protocole : c'est ce contrat qui autorise cet état mutable sans verrou.
@MainActor
final class ControleurAppsDouble: ControleurApps {
    /// pid de chaque app lancée. Une app absente d'ici n'est pas lancée.
    var pidsParBundleID: [String: pid_t]
    /// Apps installées que `lancer` peut démarrer. Une app hors de cet ensemble échoue au
    /// lancement, comme un bundleID introuvable sur le disque.
    var installees: Set<String>
    /// Nombre de sondages `fenetreVisibleDansNotch` qui répondront `false` avant que la fenêtre
    /// apparaisse. Absent = visible immédiatement. `Int.max` = n'apparaît jamais (le cas du
    /// timeout : l'app se lance mais ne dessine rien dans l'encoche).
    var sondagesAvantApparition: [String: Int] = [:]
    /// Apps qui épinglent leurs fenêtres dans un Space privé : `masquer` rend `false` et
    /// l'écran ne change pas. C'est boringNotch.
    var resistantes: Set<String> = []

    private(set) var masquees: Set<String> = []
    private(set) var journal: [ActionControleur] = []
    private var prochainPid: pid_t = 9000

    init(lancees: [String: pid_t] = [:], installees: Set<String> = []) {
        pidsParBundleID = lancees
        self.installees = installees.union(lancees.keys)
    }

    func lancer(bundleID: String) async -> Bool {
        journal.append(.lance(bundleID))
        guard installees.contains(bundleID) else { return false }
        if pidsParBundleID[bundleID] == nil {
            prochainPid += 1
            pidsParBundleID[bundleID] = prochainPid
        }
        masquees.remove(bundleID)
        return true
    }

    func tuer(pid: pid_t) -> Bool {
        journal.append(.tue(pid))
        guard let bundleID = bundleID(de: pid) else { return false }
        pidsParBundleID.removeValue(forKey: bundleID)
        masquees.remove(bundleID)
        return true
    }

    func masquer(_ masquee: Bool, pid: pid_t) -> Bool {
        journal.append(.masque(masquee, pid))
        guard let bundleID = bundleID(de: pid) else { return false }
        // Une app résistante accepte l'ordre et ne change rien : le constat est `false`, et
        // c'est bien ce que mesure le vrai `ControleurAppsSysteme` par recomptage.
        guard !resistantes.contains(bundleID) else { return false }
        if masquee { masquees.insert(bundleID) } else { masquees.remove(bundleID) }
        return true
    }

    func fenetreVisibleDansNotch(pid: pid_t) -> Bool {
        guard let bundleID = bundleID(de: pid), !masquees.contains(bundleID) else { return false }
        let restants = sondagesAvantApparition[bundleID] ?? 0
        guard restants > 0 else { return true }
        if restants != .max { sondagesAvantApparition[bundleID] = restants - 1 }
        return false
    }

    func pid(pour bundleID: String) -> pid_t? { pidsParBundleID[bundleID] }

    private func bundleID(de pid: pid_t) -> String? {
        pidsParBundleID.first(where: { $0.value == pid })?.key
    }
}

// MARK: - Le double tient le contrat du protocole

@MainActor
struct ControleurAppsDoubleTests {
    private let vibe = "app.vibeisland.macos"
    private let boring = "com.thecoolbeans.boringnotch"

    @Test("Une app lancée obtient un pid et sa fenêtre est visible dans l'encoche")
    func lancementRendLAppVisible() async throws {
        let double = ControleurAppsDouble(installees: [vibe])
        #expect(double.pid(pour: vibe) == nil)

        #expect(await double.lancer(bundleID: vibe))
        let pid = try #require(double.pid(pour: vibe))
        #expect(double.fenetreVisibleDansNotch(pid: pid))
    }

    @Test("Une app qui n'est pas installée ne se lance pas")
    func lancementDUneAppAbsente() async {
        let double = ControleurAppsDouble()
        #expect(await double.lancer(bundleID: vibe) == false)
        #expect(double.pid(pour: vibe) == nil)
    }

    @Test("La fenêtre n'apparaît qu'au sondage prévu — le scénario que la bascule devra sonder")
    func apparitionDifferee() throws {
        let double = ControleurAppsDouble(lancees: [vibe: 100])
        double.sondagesAvantApparition[vibe] = 3

        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)
        #expect(double.fenetreVisibleDansNotch(pid: 100)) // 4e sondage : elle est là
    }

    @Test("Une fenêtre qui n'apparaît jamais ne finit pas par apparaître — le cas du timeout")
    func apparitionJamais() {
        let double = ControleurAppsDouble(lancees: [vibe: 100])
        double.sondagesAvantApparition[vibe] = Int.max

        for _ in 0..<200 { #expect(double.fenetreVisibleDansNotch(pid: 100) == false) }
    }

    @Test("Masquer retire la fenêtre de l'encoche, réafficher la ramène")
    func masquagePuisReaffichage() {
        let double = ControleurAppsDouble(lancees: [vibe: 100])

        #expect(double.masquer(true, pid: 100))
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)
        #expect(double.masquer(false, pid: 100))
        #expect(double.fenetreVisibleDansNotch(pid: 100))
    }

    @Test("Une app résistante refuse le masquage et reste visible")
    func appResistante() {
        let double = ControleurAppsDouble(lancees: [boring: 200])
        double.resistantes = [boring]

        #expect(double.masquer(true, pid: 200) == false)
        #expect(double.fenetreVisibleDansNotch(pid: 200))
    }

    @Test("Tuer fait disparaître l'app : plus de pid, plus de fenêtre")
    func terminaison() {
        let double = ControleurAppsDouble(lancees: [boring: 200])

        #expect(double.tuer(pid: 200))
        #expect(double.pid(pour: boring) == nil)
        #expect(double.fenetreVisibleDansNotch(pid: 200) == false)
        #expect(double.tuer(pid: 200) == false) // déjà mort
    }

    @Test("Le journal garde l'ordre des actions, ce dont dépendra le test « pas tuée trop tôt »")
    func journalOrdonne() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [boring])

        _ = await double.lancer(bundleID: boring)
        let pidBoring = double.pid(pour: boring)
        _ = double.masquer(true, pid: 100)
        _ = double.tuer(pid: 100)

        let attendu: [ActionControleur] = [.lance(boring), .masque(true, 100), .tue(100)]
        #expect(double.journal == attendu)
        #expect(pidBoring != nil)
    }
}

// MARK: - La machine à états de la bascule
//
// C'est ici que se joue la valeur de la task. Chaque test répond à une question qu'un
// utilisateur poserait devant son encoche : est-ce que l'app d'avant a bien attendu que la
// suivante soit là pour disparaître ? est-ce qu'un échec me laisse avec un notch vide ?

@MainActor
struct BasculeTests {
    private let vibe = "app.vibeisland.macos"       // régissable : se laisse masquer
    private let boring = "com.thecoolbeans.boringnotch" // résistante : Space privé, seul le cycle de vie l'atteint
    private let notchy = "dev.notchy.notchy"        // seconde régissable, pour les bascules AX pures

    private func app(_ bundleID: String, _ support: SupportStatus, pid: pid_t? = nil) -> NotchAppInfo {
        NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
    }

    /// Sondages rapides : la logique testée est l'ordre des actions, pas la durée réelle.
    private func bascule(_ double: ControleurAppsDouble, delaiMax: Duration = .seconds(2)) -> Bascule {
        Bascule(controleur: double, intervalleSondage: .milliseconds(1), delaiMax: delaiMax)
    }

    @Test("La cible apparaît au 3e sondage : l'actuelle est tuée, et pas avant")
    func actuelleTueeSeulementApresApparitionDeLaCible() async {
        let double = ControleurAppsDouble(lancees: [boring: 200], installees: [vibe])
        double.resistantes = [boring]
        double.sondagesAvantApparition[vibe] = 3

        let resultat = await bascule(double).basculer(
            vers: app(vibe, .supported), depuis: app(boring, .unsupported, pid: 200)
        )

        #expect(resultat == .reussie)
        // Les trois sondages négatifs ont bien été consommés : le `tue` est arrivé après.
        #expect(double.sondagesAvantApparition[vibe] == 0)
        #expect(double.journal == [.lance(vibe), .tue(200)])
        #expect(double.pid(pour: boring) == nil)
        #expect(double.pid(pour: vibe) != nil)
    }

    @Test("La cible n'apparaît jamais : l'actuelle est intacte et la bascule remonte l'échec")
    func timeoutNeToucheJamaisALActuelle() async {
        let double = ControleurAppsDouble(lancees: [boring: 200], installees: [vibe])
        double.resistantes = [boring]
        double.sondagesAvantApparition[vibe] = .max

        let resultat = await bascule(double, delaiMax: .milliseconds(30)).basculer(
            vers: app(vibe, .supported), depuis: app(boring, .unsupported, pid: 200)
        )

        #expect(resultat == .cibleJamaisApparue)
        #expect(double.journal == [.lance(vibe)]) // ni `tue`, ni `masque`
        #expect(double.pid(pour: boring) == 200)  // l'utilisateur garde l'app qu'il avait
        #expect(double.fenetreVisibleDansNotch(pid: 200))
    }

    @Test("Cible régissable et déjà lancée : la voie rapide, deux masquages et aucun lancement")
    func voieRapideSansLancement() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100, notchy: 300])

        let resultat = await bascule(double).basculer(
            vers: app(vibe, .supported, pid: 100), depuis: app(notchy, .supported, pid: 300)
        )

        #expect(resultat == .reussie)
        #expect(double.journal == [.masque(false, 100), .masque(true, 300)])
        #expect(double.fenetreVisibleDansNotch(pid: 100))
        #expect(double.fenetreVisibleDansNotch(pid: 300) == false)
    }

    @Test("Une actuelle régissable est masquée, jamais tuée")
    func actuelleRegissableEstMasquee() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [boring])
        double.resistantes = [boring]

        let resultat = await bascule(double).basculer(
            vers: app(boring, .unsupported), depuis: app(vibe, .supported, pid: 100)
        )

        #expect(resultat == .reussie)
        #expect(double.journal == [.lance(boring), .masque(true, 100)])
        #expect(double.pid(pour: vibe) == 100) // toujours vivante, juste masquée
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)
    }

    @Test("Une seule app au catalogue : la bascule la masque, puis la réaffiche")
    func uneSeuleAppBasculeSurElleMeme() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100])
        let seule = app(vibe, .supported, pid: 100)
        let bascule = bascule(double)

        #expect(await bascule.basculer(vers: seule, depuis: seule) == .reussie)
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)

        #expect(await bascule.basculer(vers: seule, depuis: seule) == .reussie)
        #expect(double.fenetreVisibleDansNotch(pid: 100))
        #expect(double.journal == [.masque(true, 100), .masque(false, 100)])
    }

    @Test("Une cible qui n'est plus installée ne coûte pas l'app courante")
    func lancementRefuseNeToucheJamaisALActuelle() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100]) // `boring` n'est pas installée

        let resultat = await bascule(double).basculer(
            vers: app(boring, .unsupported), depuis: app(vibe, .supported, pid: 100)
        )

        #expect(resultat == .lancementImpossible)
        #expect(double.journal == [.lance(boring)])
        #expect(double.fenetreVisibleDansNotch(pid: 100))
    }
}
