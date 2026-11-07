//
// GardesExtinctionTests.swift — QA passe 6 : le chemin neuf qui mène à tuer, et les deux gardes
// qui lui manquaient.
//
// **La racine, unique.** `57b735f` ouvre la PREMIÈRE voie de `poursuivreFermeture` vers
// `eteindre` — donc vers `quitterEtAttendre`, donc vers `tuer(pid:)` — sur une app que Bouncer
// n'avait pas encore touchée. Avant lui, la surveillance finissait sur `return await allumer(app)`
// et ne pouvait rien tuer d'autre que la cible qu'elle venait déjà de tuer. `basculer` protège ce
// dernier filet par deux gardes ; le chemin neuf n'en avait aucun.
//   - **D1** — l'annulation est REÇUE (`WindowManager.basculer` appelle `cancel()`) mais pas
//     OBSERVÉE entre `allumer` et `eteindre`. Entre les deux il y a `lancer` tout entier, et si la
//     fenêtre est là au premier sondage, la boucle rend `.reussie` sans jamais passer par
//     `dormir()`, la seule porte qui observe l'annulation.
//   - **D2** — le droit Accessibilité retiré en cours de surveillance fait tuer la précédente. Le
//     masquage part dans le vide, le recomptage rend `false`, et le dernier filet quitte l'app.
//   - **§3** — la quatrième boucle de sondage, `ControleurAppsSysteme.masquer`, gardait son
//     `try? await Task.sleep` nu, et ce commit y fait passer une tâche annulable pour la première
//     fois.
//
// **Ce que chaque test épingle, et ce qu'il n'épingle pas.** Les deux gardes se ressemblent et se
// couvrent mal : chaque test dit donc en tête lequel il fait tomber. La contre-épreuve est au bas
// du fichier, dans le rapport de passe.
//

import Foundation
import Testing
@testable import BouncerCore

private let vibe = "app.vibeisland.macos"
private let boring = "theboringteam.boringnotch"

private func info(_ bundleID: String, _ support: SupportStatus, pid: pid_t?) -> NotchAppInfo {
    NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
}

/// Le droit AX, révocable en cours de route. Une classe et pas un `var` capturé : la bascule et le
/// double doivent voir la MÊME révocation, comme les deux mesures de la vraie machine.
@MainActor
private final class DroitAX {
    var accorde = true
}

/// La surveillance dans l'état exact où les deux défauts vivent : la cible est DÉJÀ morte (la
/// boucle d'attente passe tout droit), et la précédente est résistante au masquage — donc la seule
/// sortie de `eteindre` est le dernier filet, celui qui tue.
@MainActor
private func surveillancePreteATuer(droit: DroitAX)
    -> (double: ControleurAppsDouble, bascule: Bascule, cible: NotchAppInfo, precedente: NotchAppInfo) {
    let double = ControleurAppsDouble(lancees: [vibe: 100, boring: 200], installees: [vibe, boring])
    _ = double.tuer(pid: 100)
    double.resistantes = [boring]
    let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                          delaiMax: .milliseconds(200), delaiMort: .milliseconds(20),
                          trustAccorde: { droit.accorde }, encocheMesurable: { true })
    return (double, bascule, info(vibe, .supported, pid: 100), info(boring, .unsupported, pid: 200))
}

// MARK: - D1 — l'annulation doit être observée AVANT l'extinction, pas seulement avant la relance

@MainActor
struct AnnulationAvantExtinctionTests {

    /// Le rejeu QA6-A. L'annulation arrive PENDANT `lancer` — la fenêtre réelle, plusieurs
    /// centaines de millisecondes de `NSWorkspace.openApplication` — puis la fenêtre est là au
    /// premier sondage, donc la boucle d'apparition ne dort jamais et personne ne regarde plus
    /// l'annulation. Avant le correctif : `verdict = .reussie`, journal
    /// `[tue(100), lance(vibe), masque(true, 200), tue(200)]`, `boringVivant = false` — Bouncer
    /// tuait la précédente sur ordre d'une tâche à qui on venait de dire de s'arrêter.
    ///
    /// **Ce test épingle le SECOND `guard !Task.isCancelled`, et lui seul.** Le premier est déjà
    /// franchi quand l'annulation arrive ; le retirer ne fait pas tomber ce test-ci (il est
    /// épinglé par `surveillanceAnnuleeAvantLaRelanceNeRelancePas`).
    @Test("Une surveillance annulée pendant la relance ne tue pas la précédente")
    func annulationPendantLaRelanceNeTuePasLaPrecedente() async {
        let (double, bascule, cible, precedente) = surveillancePreteATuer(droit: DroitAX())

        // La tâche est créée avant que le crochet ne puisse la voir : la boîte les relie.
        let boite = BoiteTache()
        double.pendantLeLancement = { boite.tache?.cancel() }
        let tache = Task { await bascule.poursuivreFermeture(de: cible, puisRelancer: true,
                                                             puisEteindre: precedente) }
        boite.tache = tache

        let verdict = await tache.value

        // Le verdict est de toute façon jeté par `surveiller` ; ce qui compte est en dessous.
        #expect(verdict == .cibleFermetureEnCours)
        // LA propriété : la précédente n'a pas été touchée. Ni masquée, ni tuée, ni morte.
        #expect(double.journal.contains(.tue(200)) == false)
        #expect(double.journal.contains(.masque(true, 200)) == false)
        #expect(double.pid(pour: boring) == 200)
        // Et la moitié qui était juste a bien eu lieu : la cible tuée est rendue à l'utilisateur.
        #expect(double.journal.contains(.lance(vibe)))
    }

    /// Le pendant : sans annulation, le même montage range bel et bien la précédente. Sans ce
    /// contrôle, un garde trop large — par exemple posé avant `allumer` — passerait le test
    /// ci-dessus tout en cassant le cas de tous les jours.
    @Test("Sans annulation, la même surveillance range la précédente comme avant")
    func sansAnnulationLaPrecedenteEstBienRangee() async {
        let (double, bascule, cible, precedente) = surveillancePreteATuer(droit: DroitAX())

        let verdict = await bascule.poursuivreFermeture(de: cible, puisRelancer: true,
                                                        puisEteindre: precedente)

        #expect(verdict == .reussie)
        #expect(double.journal.contains(.tue(200)))
        #expect(double.pid(pour: boring) == nil)
        #expect(double.pid(pour: vibe) != nil)
    }
}

/// Le lien entre la tâche et le crochet qui doit l'annuler : le crochet est posé avant que la
/// tâche n'existe. Une classe, parce qu'une capture de `var` locale par une fermeture posée sur le
/// double serait lue au moment de l'appel, pas à celui de la pose — et cette différence-là est
/// exactement ce qu'on ne veut pas laisser au hasard dans un test de course.
@MainActor
private final class BoiteTache {
    var tache: Task<ResultatBascule, Never>?
}

// MARK: - D2 — le droit retiré interdit d'éteindre, jamais de relancer

@MainActor
struct DroitRetirePendantLaSurveillanceTests {

    /// Le rejeu QA6-B. Le droit est retiré entre le geste et la surveillance. Avant le correctif :
    /// `poursuivreFermeture = .reussie`, journal `[…, masque(true, 200), tue(200)]`,
    /// `boringVivant = false` — le masquage part dans le vide, le recomptage rend `false`, et le
    /// dernier filet QUITTE une app qui a peut-être du travail non enregistré.
    ///
    /// **Ce test épingle le `guard trustAccorde()` de `poursuivreFermeture`, et lui seul.** Le
    /// garde d'entrée de `basculer` n'est pas sur ce chemin : c'est tout le défaut.
    @Test("Le droit Accessibilité retiré pendant la surveillance n'autorise pas à tuer la précédente")
    func droitRetireNeTuePasLaPrecedente() async {
        let droit = DroitAX()
        let (double, bascule, cible, precedente) = surveillancePreteATuer(droit: droit)

        // Le retrait, dans les deux mesures à la fois : le produit le voit par `trustAccorde`, le
        // système le fait subir à `masquer`, qui part alors dans le vide.
        droit.accorde = false
        double.accessibiliteRevoquee = true

        let verdict = await bascule.poursuivreFermeture(de: cible, puisRelancer: true,
                                                        puisEteindre: precedente)

        // Un verdict à lui : ni `.reussie` (l'encoche en porte deux), ni
        // `.precedenteFermetureEnCours` (personne n'a tué, il n'y a aucune mort à attendre).
        #expect(verdict == .precedenteNonRangeableSansAccessibilite)
        #expect(double.journal.contains(.tue(200)) == false)
        // On ne touche même pas l'API AX : le garde est AVANT `eteindre`, pas dedans.
        #expect(double.journal.contains(.masque(true, 200)) == false)
        #expect(double.pid(pour: boring) == 200)
    }

    /// L'autre moitié du geste, et c'est elle qui fait du correctif un arbitrage plutôt qu'un
    /// garde de plus : la RELANCE, elle, doit partir sans droit. Refuser laisserait morte une app
    /// que Bouncer a tuée lui-même. Un `guard trustAccorde()` posé en tête de
    /// `poursuivreFermeture` — la forme « symétrique », celle qui paraît propre — fait tomber ce
    /// test-ci.
    @Test("Le droit retiré n'empêche pas de rendre à l'utilisateur l'app que Bouncer a tuée")
    func droitRetireNEmpechePasLaRelance() async {
        let droit = DroitAX()
        let (double, bascule, cible, precedente) = surveillancePreteATuer(droit: droit)
        droit.accorde = false
        double.accessibiliteRevoquee = true

        _ = await bascule.poursuivreFermeture(de: cible, puisRelancer: true, puisEteindre: precedente)

        let neuf = double.pid(pour: vibe)
        #expect(neuf != nil)                              // l'app tuée est rendue
        #expect(neuf != 100)                              // et c'est une instance neuve
        #expect(double.fenetreVisibleDansNotch(pid: neuf!))
    }
}

// MARK: - Le câblage : ce que `WindowManager` dit à l'utilisateur du droit retiré

@MainActor
struct CablageDroitRetireTests {

    /// L'utilisateur voit deux apps dans l'encoche. Il doit savoir POURQUOI — le droit a été
    /// retiré — et qu'un geste de plus n'y changera rien tant qu'il ne l'aura pas rendu. Le
    /// message est celui de la révocation, qui existait déjà pour cet événement ; il nomme
    /// seulement, en plus, l'app restée à l'écran.
    @Test("Câblage : le droit retiré pendant la surveillance nomme l'app restée dans l'encoche")
    func lUtilisateurApprendPourquoiIlVoitDeuxApps() async {
        let suite = "GardesExtinction.\(UUID().uuidString)"
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
        while wm.apps.contains(where: { $0.support == .testing }) { await Task.yield() }
        #expect(wm.bundleIDActive == boring)

        double.sondagesAvantApparition[vibe] = 1   // le démasquage ne ramène rien -> repli tuer
        double.sondagesAvantMort[vibe] = 30        // 60 ms, hors des 5 ms de courtoisie
        double.resistantes = [boring]              // la seule sortie de `eteindre` serait de tuer

        await wm.basculer(vers: vibe)
        let surveillance = wm.surveillanceFermeture
        #expect(surveillance != nil)

        // Le droit part MAINTENANT : on tient le main actor, la surveillance n'a pas encore
        // tourné. C'est le scénario de `refreshTrustState`, joué à l'instant où il fait mal.
        droit.accorde = false
        double.accessibiliteRevoquee = true
        await surveillance?.value

        // La cible est rendue et enregistrée : la moitié qui a réussi ne se perd pas.
        #expect(double.pid(pour: vibe) != nil)
        #expect(wm.bundleIDActive == vibe)
        // La précédente est vivante, visible, et le modèle ne la dit PAS masquée.
        #expect(double.pid(pour: boring) == 200)
        #expect(wm.apps.first { $0.bundleID == boring }?.isHiddenByUs != true)
        // Et le message dit les deux choses qui comptent : la cause, et l'app qu'on voit.
        #expect(wm.echecBascule?.detail == texte("error.accessRevoked.twoApps", boring))
        // Pas de surveillance chaînée : personne n'a tué la précédente, il n'y a rien à attendre.
        #expect(wm.surveillanceFermeture == nil)
    }
}

// MARK: - §3 — la quatrième boucle passe par la même porte

@MainActor
struct PorteDeSondageTests {

    /// La porte elle-même. Elle ne rend `false` que sur annulation ; hors annulation, aucune
    /// boucle ne doit sortir avant sa propre condition.
    @Test("La porte de sondage rend false sur annulation, true sinon")
    func laPorteNeSOuvreQueSurAnnulation() async {
        #expect(await dormirSondage(.milliseconds(1)))

        let tache = Task { await dormirSondage(.milliseconds(1)) }
        tache.cancel()
        #expect(await tache.value == false)
    }

    /// La boucle de propagation du VRAI contrôleur, celle que `eteindre(precedente)` fait
    /// désormais tourner sous une tâche annulable. Avec le `try?` nu, l'annulation faisait repartir
    /// la boucle sans dormir jusqu'au plafond : ~7 tours de 15 ms devenaient 100 ms de boucle
    /// serrée sur le main actor.
    ///
    /// Le seul test de ce fichier qui touche le VRAI contrôleur — il n'y a rien à doubler, c'est
    /// la boucle elle-même qu'on mesure. Le seuil est large exprès : il sépare « sort tout de
    /// suite » de « tourne 100 ms », pas deux durées voisines.
    @Test("La boucle de propagation du contrôleur système sort à l'annulation au lieu de s'emballer")
    func laPropagationSortALAnnulation() async {
        let controleur = ControleurAppsSysteme()
        // Le premier appel du process paie la mise en route de la connexion Accessibility et du
        // premier `CGWindowList` — ~100 ms, du même ordre que ce qu'on mesure. On le jette.
        _ = await controleur.masquer(true, pid: 999_999)

        // Le contrôle : sans annulation, la boucle tourne jusqu'à son plafond de 100 ms. Le pid
        // n'existe pas, donc le décompte de fenêtres ne change jamais et rien ne l'en sort avant.
        // C'est le pire cas, et c'est celui que `eteindre(precedente)` fait désormais tourner sous
        // une tâche annulable.
        let debutPlein = ContinuousClock.now
        _ = await controleur.masquer(true, pid: 999_999)
        let plein = ContinuousClock.now - debutPlein

        let debutAnnule = ContinuousClock.now
        let tache = Task { _ = await controleur.masquer(true, pid: 999_999) }
        tache.cancel()
        _ = await tache.value
        let annule = ContinuousClock.now - debutAnnule

        #expect(plein > .milliseconds(90))
        // Mesuré : 1,7 ms avec la porte, 101 ms avec le `try?` nu — la boucle repartait sans avoir
        // dormi, à pleine vitesse sur le main actor, jusqu'au plafond.
        #expect(annule < .milliseconds(30))
    }
}
