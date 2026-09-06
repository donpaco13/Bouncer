//
// BasculeTests.swift — le double de `ControleurApps`, et la preuve qu'il se comporte comme
// le vrai système sur les points dont la machine à états dépendra.
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
    case reaffiche(pid_t)
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
    /// Nombre de sondages `pid(pour:)` pendant lesquels un process TUÉ reste encore là. Absent =
    /// mort immédiate. `.max` = l'app ne meurt jamais (une feuille « Enregistrer les
    /// modifications ? » attend l'utilisateur, ou l'app ne répond plus).
    ///
    /// Sans ce délai, le double ment sur le seul point où le vrai système ment au code appelant :
    /// `terminate()` poste un Apple Event et rend `true` aussitôt, bien avant que le process ne
    /// s'arrête. Un double qui tue sur-le-champ rend intestable tout le chemin du meurtre — et
    /// c'est très exactement ce qui a laissé passer la relance sur un process mourant.
    var sondagesAvantMort: [String: Int] = [:]

    /// Les process à qui on a demandé de partir et qui ne sont pas encore partis.
    private var mourantes: [String: Int] = [:]

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
        // Un process en train de mourir n'est PAS relancé : `openApplication` rend l'instance
        // mourante au lieu d'en démarrer une neuve. C'est ce comportement-là qui faisait
        // disparaître l'app pour de bon quand `allumer` relançait sans attendre la mort.
        if mourantes[bundleID] != nil { return true }
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
        // `true` dès que la demande est partie, mort ou pas : c'est le contrat de `terminate()`,
        // et c'est précisément pour ça qu'un appelant ne peut pas s'y fier.
        let delai = sondagesAvantMort[bundleID] ?? 0
        guard delai == 0 else { mourantes[bundleID] = delai; return true }
        retirer(bundleID)
        return true
    }

    private func retirer(_ bundleID: String) {
        mourantes.removeValue(forKey: bundleID)
        pidsParBundleID.removeValue(forKey: bundleID)
        masquees.remove(bundleID)
    }

    func masquer(_ masquee: Bool, pid: pid_t) async -> Bool {
        journal.append(.masque(masquee, pid))
        guard !accessibiliteRevoquee else { return false }
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

    /// Sonder un process mourant le rapproche de sa fin — c'est le seul horloge du double, et
    /// elle est celle-là même que `quitterEtAttendre` fait tourner.
    func pid(pour bundleID: String) -> pid_t? {
        if let restants = mourantes[bundleID], restants != .max {
            if restants <= 1 { retirer(bundleID) } else { mourantes[bundleID] = restants - 1 }
        }
        return pidsParBundleID[bundleID]
    }

    /// Le pendant du vrai : il lève le masquage sans rien mesurer. Un pid inconnu ne fait rien,
    /// comme un `AXUIElementSetAttributeValue` sur un process mort.
    func reafficherSansAttendre(pid: pid_t) {
        journal.append(.reaffiche(pid))
        guard !accessibiliteRevoquee, let bundleID = bundleID(de: pid) else { return }
        masquees.remove(bundleID)
    }

    /// Le droit Accessibilité retiré pendant que Bouncer tourne : `masquer` part dans le vide et
    /// l'écran ne bouge pas, dans les DEUX sens. C'est ce que `resistantes` ne simule pas — une
    /// app résistante refuse le masquage mais se laisse démasquer.
    var accessibiliteRevoquee = false

    private func bundleID(de pid: pid_t) -> String? {
        pidsParBundleID.first(where: { $0.value == pid })?.key
    }
}

// MARK: - Le double tient le contrat du protocole

@MainActor
struct ControleurAppsDoubleTests {
    private let vibe = "app.vibeisland.macos"
    private let boring = "theboringteam.boringnotch"

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
    func masquagePuisReaffichage() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100])

        #expect(await double.masquer(true, pid: 100))
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)
        #expect(await double.masquer(false, pid: 100))
        #expect(double.fenetreVisibleDansNotch(pid: 100))
    }

    @Test("Une app résistante refuse le masquage et reste visible")
    func appResistante() async {
        let double = ControleurAppsDouble(lancees: [boring: 200])
        double.resistantes = [boring]

        #expect(await double.masquer(true, pid: 200) == false)
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
        _ = await double.masquer(true, pid: 100)
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
    private let boring = "theboringteam.boringnotch" // résistante : Space privé, seul le cycle de vie l'atteint
    private let notchy = "dev.notchy.notchy"        // seconde régissable, pour les bascules AX pures

    private func app(_ bundleID: String, _ support: SupportStatus, pid: pid_t? = nil) -> NotchAppInfo {
        NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
    }

    /// Sondages rapides : la logique testée est l'ordre des actions, pas la durée réelle.
    ///
    /// `trustAccorde: { true }` parce que ces tests-là portent sur la machine à états, pas sur son
    /// garde d'entrée : sans cette injection ils dépendraient du droit Accessibilité réel du
    /// binaire de test, donc de la machine qui les exécute. Le garde a son propre test, dans
    /// `RobustesseTests`.
    private func bascule(_ double: ControleurAppsDouble, delaiMax: Duration = .seconds(2)) -> Bascule {
        Bascule(
            controleur: double, intervalleSondage: .milliseconds(1), delaiMax: delaiMax,
            trustAccorde: { true }
        )
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


// MARK: - Le meurtre est vérifié : jamais d'app perdue, jamais d'app fantôme

/// Ce que garantit l'attente de mort ajoutée à `quitterEtAttendre`. Les trois cas viennent du même
/// défaut : `tuer` était appelé sans jamais constater que le process était parti.
@MainActor
struct MeurtreSurTests {
    private let vibe = "app.vibeisland.macos"
    private let boring = "theboringteam.boringnotch"

    private func info(_ bundleID: String, _ support: SupportStatus, pid: pid_t?) -> NotchAppInfo {
        NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
    }

    /// Le cas le plus grave : la cible est tuée par le repli de `allumer` puis relancée. Tant que
    /// la mort n'était pas attendue, la relance retombait sur le process mourant et l'app
    /// disparaissait pour de bon. Ici la cible doit être VIVANTE et dans l'encoche à l'arrivée.
    @Test("Le repli de allumer relance vraiment la cible qu'il vient de tuer")
    func repliAllumerNePerdPasLaCible() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        // Régissable au catalogue, mais le démasquage ne ramène rien à l'écran : la voie rapide
        // échoue et bascule sur le repli tuer-puis-relancer.
        // Un seul sondage négatif : de quoi faire échouer la voie rapide et déclencher le repli.
        // La relance, elle, repart d'un compteur épuisé — la nouvelle instance apparaît aussitôt.
        double.sondagesAvantApparition[vibe] = 1
        // Et surtout : le process met trois sondages à mourir, comme un vrai. Relancer avant
        // qu'il soit parti ne redémarre rien.
        double.sondagesAvantMort[vibe] = 3

        // `delaiMax` généreux, comme le défaut du helper d'à côté : ce test-ci attend un SUCCÈS,
        // pas un délai. Son budget de 50 ms était une horloge murale, et il a suffi qu'un test
        // voisin construise un vrai `WindowManager` — première touche de `AXIsProcessTrusted()`
        // et de `CGWindowList`, ~90 ms de main actor à elles deux, une seule fois par processus —
        // pour qu'il expire sur une lenteur qui n'est pas la sienne. La boucle sort dès que la
        // cible est là : le budget large ne coûte rien.
        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(1),
                              delaiMax: .seconds(2), trustAccorde: { true })
        let resultat = await bascule.basculer(vers: info(vibe, .supported, pid: 100), depuis: nil)

        #expect(resultat == .reussie)
        // La preuve : un pid, donc une app vivante. Et un pid DIFFÉRENT de celui qu'on a tué.
        let nouveau = double.pid(pour: vibe)
        #expect(nouveau != nil)
        #expect(nouveau != 100)
        #expect(double.journal.contains(.tue(100)))
        #expect(double.journal.contains(.lance(vibe)))
    }

    /// Une app qui refuse de quitter ne doit jamais passer pour rangée : elle est toujours dans
    /// l'encoche, à côté de la nouvelle. Avant, `eteindre` rendait un succès muet et
    /// `WindowManager` la marquait masquée.
    @Test("Une précédente qui refuse de quitter est signalée, pas passée sous silence")
    func precedenteQuiRefuseDeQuitterEstSignalee() async {
        let double = ControleurAppsDouble(lancees: [boring: 200], installees: [boring, vibe])
        double.resistantes = [boring]              // pas masquable : la seule sortie est de la quitter
        double.sondagesAvantMort[boring] = .max    // et elle ne quitte pas

        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(1),
                              delaiMax: .milliseconds(30), trustAccorde: { true })
        let resultat = await bascule.basculer(
            vers: info(vibe, .testing, pid: nil), depuis: info(boring, .unsupported, pid: 200)
        )

        #expect(resultat == .precedenteResteEnPlace)
        // La cible, elle, est bien arrivée : l'échec ne porte que sur la précédente.
        #expect(double.pid(pour: vibe) != nil)
        #expect(double.pid(pour: boring) == 200)
    }

    /// La bascule normale de boringNotch — celle de tous les jours — reste un succès franc, et
    /// l'app est réellement morte quand on rend la main. Sans quoi `WindowManager` la marquerait
    /// `isHiddenByUs` sur la foi d'un pid encore vivant.
    @Test("Une précédente qui quitte pour de bon rend un succès, et son pid a disparu")
    func precedenteQuitteeEstVraimentMorte() async {
        let double = ControleurAppsDouble(lancees: [boring: 200], installees: [boring, vibe])
        double.resistantes = [boring]

        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(1),
                              delaiMax: .milliseconds(30), trustAccorde: { true })
        let resultat = await bascule.basculer(
            vers: info(vibe, .testing, pid: nil), depuis: info(boring, .unsupported, pid: 200)
        )

        #expect(resultat == .reussie)
        #expect(double.pid(pour: boring) == nil)
    }
}
