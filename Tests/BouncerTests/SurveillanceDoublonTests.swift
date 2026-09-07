//
// SurveillanceDoublonTests.swift — QA passe 5 : le correctif qui échangeait la perte d'app
// contre le doublon, et la sortie de test qui manquait pour le voir.
//
// **Ce que la passe 5 a trouvé.** `d0fdc18` répare la perte d'app (D2 de la passe 4) et introduit
// à sa place l'état que le produit existe pour empêcher : DEUX APPS DANS L'ENCOCHE.
//   - **D1** — `basculer` s'arrête sur `.cibleFermetureEnCours` AVANT `eteindre(actuelle)` : la
//     précédente n'est jamais éteinte, et la surveillance rallume la cible par-dessus.
//   - **D2** — l'annulation est gardée dans la boucle d'attente de mort, pas à la porte de
//     `allumer` : la relance part quand même sur une tâche annulée, et la boucle d'apparition
//     tourne à vide sur le main actor (29 899 sondages en 300 ms contre 23 sans annulation).
//   - **D3** — `poursuivreFermeture` ne repasse par aucun garde d'entrée, ce qui est VOULU (sans
//     relance l'app reste morte) mais laisse un message qui accuse l'app d'un capot fermé.
//
// **Et pourquoi aucun test ne les voyait — la quatrième cause, qui est la première.** Les deux
// verdicts neufs n'atteignaient leur `case` dans AUCUN test : `sonder()` passe par
// `scanNotchApps`, qui lit un vrai `CGWindowList` et un vrai `NSRunningApplication`, donc avec
// `geometrie: { nil }` la liste `apps` restait vide, `bundleIDActive` restait `nil`, `actuelle`
// aussi, et `supportVerdictCache` ne se remplissait jamais. Les trois défauts vivaient très
// exactement là où aucun test ne pouvait aller. `WindowManager.init(scan:)` est la sortie qui
// manquait, dans le même esprit que `geometrie:` et `controleur:` — et ce fichier s'en sert pour
// prouver les trois défauts au niveau du CÂBLAGE, pas seulement au niveau de `Bascule`.
//
// **L'horloge, comme dans `FermetureLenteTests`** : le double compte en SONDAGES. Les tests de
// `Bascule` gardent les durées de production (`delaiMort` 600 ms, `delaiMax` 5 s) et resserrent
// le seul intervalle de sondage ; les tests de câblage raccourcissent tout, parce que ce qu'ils
// vérifient est un enchaînement, pas une frontière temporelle.
//

import Foundation
import Testing
@testable import BouncerCore

private let vibe = "app.vibeisland.macos"
private let boring = "theboringteam.boringnotch"

private func info(_ bundleID: String, _ support: SupportStatus, pid: pid_t?) -> NotchAppInfo {
    NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
}

/// L'écran à encoche, débranchable en cours de route. Une classe et pas un `var` capturé : les
/// deux fermetures injectées (`geometrie` et `encocheMesurable`) doivent voir la MÊME bascule.
@MainActor
final class EcranSimule {
    var branche = true
    let zone = CGRect(x: 576, y: 846, width: 200, height: 32)
    let cadre = CGRect(x: 0, y: 0, width: 1352, height: 878)
    var geometrie: (rect: CGRect, ecran: String, cadre: CGRect)? {
        branche ? (zone, "Écran de test", cadre) : nil
    }
}

// MARK: - D1 — la relance ne doit jamais poser une seconde app dans l'encoche

@MainActor
struct DoublonDansLEncocheTests {

    /// Le rejeu exact de la QA, aux durées de production. Avant le correctif : `.reussie` rendu
    /// avec `vibeVisible = true` ET `boringVisible = true`, journal
    /// `[masque(false, 100), tue(100), lance(vibe)]` — la précédente n'ayant jamais été touchée.
    @Test("La relance d'une cible tuée range la précédente au lieu de s'ajouter à elle")
    func laRelanceNeLaissePasDeuxAppsDansLEncoche() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100, boring: 200], installees: [vibe, boring])
        // Le démasquage ne ramène rien à l'écran : la voie rapide échoue et le repli
        // tuer-puis-relancer s'enclenche. C'est le seul chemin où Bouncer tue la CIBLE.
        double.sondagesAvantApparition[vibe] = 1
        double.sondagesAvantMort[vibe] = 62        // 62 × 10 ms = 620 ms, hors fenêtre de courtoisie

        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(10),
                              trustAccorde: { true }, encocheMesurable: { true })
        let cible = info(vibe, .supported, pid: 100)
        let precedente = info(boring, .supported, pid: 200)

        #expect(await bascule.basculer(vers: cible, depuis: precedente) == .cibleFermetureEnCours)
        // À CET instant, la précédente est encore là — et c'est juste : rien d'autre n'occupe
        // l'encoche, la cible vient d'être tuée. La dette n'est pas dans ce constat, elle est
        // dans ce qui doit suivre la relance.
        #expect(double.fenetreVisibleDansNotch(pid: 200))

        let final = await bascule.poursuivreFermeture(de: cible, puisRelancer: true, puisEteindre: precedente)

        #expect(final == .reussie)
        let neuf = double.pid(pour: vibe)
        #expect(neuf != nil)                              // l'app de l'utilisateur est rendue
        #expect(neuf != 100)                              // et c'est une instance neuve
        #expect(double.fenetreVisibleDansNotch(pid: neuf!))
        // LA propriété du produit : deux apps visibles en même temps fait échouer ce test.
        #expect(double.fenetreVisibleDansNotch(pid: 200) == false)
    }

    /// La précédente qui traîne à quitter APRÈS la relance : la seconde dette n'est pas soldée
    /// non plus, mais elle est reconnue et enchaînée, exactement comme la première.
    @Test("Une précédente qui traîne après la relance rend un verdict d'attente, pas un succès")
    func precedenteQuiTraineApresLaRelanceEstSignalee() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100, boring: 200], installees: [vibe, boring])
        double.sondagesAvantApparition[vibe] = 1
        double.sondagesAvantMort[vibe] = 62
        double.resistantes = [boring]              // pas masquable : la seule sortie est de la quitter
        double.sondagesAvantMort[boring] = 89      // 89 × 10 ms = 890 ms, hors courtoisie

        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(10),
                              trustAccorde: { true }, encocheMesurable: { true })
        let cible = info(vibe, .supported, pid: 100)
        let precedente = info(boring, .unsupported, pid: 200)

        #expect(await bascule.basculer(vers: cible, depuis: precedente) == .cibleFermetureEnCours)
        let final = await bascule.poursuivreFermeture(de: cible, puisRelancer: true, puisEteindre: precedente)

        #expect(final == .precedenteFermetureEnCours)     // la cible est là, la précédente s'en va
        #expect(double.pid(pour: vibe) != nil)
        // Le `terminate()` de la précédente EST parti : c'est ce qui rend le second tour de
        // surveillance finissable. Sans lui, `poursuivreFermeture(puisRelancer: false)`
        // attendrait la mort d'un process qu'on n'a jamais demandé de fermer — indéfiniment.
        // Ce second tour lui-même est déjà couvert par `precedenteMourantEn890msLibereLEncoche`.
        #expect(double.journal.contains(.tue(200)))
    }
}

// MARK: - D2 — l'annulation doit couvrir tout le chemin, pas sa première moitié

@MainActor
struct AnnulationDeLaSurveillanceTests {

    /// La moitié du chemin que le garde ne couvrait pas : la mort EST constatée, et c'est à cet
    /// instant-là qu'un geste suivant a repris la main. Avant le correctif, `allumer` partait
    /// quand même — `journal.contains(.lance(vibe)) == true` — et l'app que l'utilisateur venait
    /// d'abandonner revenait par-dessus celle qu'il avait demandée.
    ///
    /// Déterministe : la tâche hérite du main actor, que ce test tient ; son corps ne peut donc
    /// pas démarrer avant `cancel()`. Elle entre dans `poursuivreFermeture` déjà annulée, sur une
    /// app déjà morte — l'état exact où le garde manquait.
    @Test("Une surveillance annulée ne relance pas l'app que l'utilisateur vient d'abandonner")
    func surveillanceAnnuleeAvantLaRelanceNeRelancePas() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        _ = double.tuer(pid: 100)                  // morte sur-le-champ : la boucle d'attente passe tout droit

        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(10),
                              trustAccorde: { true }, encocheMesurable: { true })
        let tache = Task { await bascule.poursuivreFermeture(de: info(vibe, .supported, pid: 100),
                                                             puisRelancer: true) }
        tache.cancel()

        #expect(await tache.value == .cibleFermetureEnCours)
        #expect(double.journal.contains(.lance(vibe)) == false)
        #expect(double.pid(pour: vibe) == nil)     // elle reste au catalogue, à un clic
    }

    /// L'emballement, et il est ce que D2 coûte vraiment. Sur une tâche annulée
    /// `try? await Task.sleep` lève aussitôt et avale l'erreur : la boucle d'apparition repart
    /// sans avoir dormi, jusqu'à `delaiMax`. La QA a compté **29 899 sondages en 300 ms contre 23
    /// sans annulation** ; aux 5 s du produit, c'est ~10 000 allers-retours WindowServer et 5 s de
    /// main actor à 100 %, pendant lesquelles rien ne répond.
    ///
    /// `delaiMax` garde donc ici sa valeur de production : sans le garde, ce test ne se contente
    /// pas d'échouer sur le compte, il met cinq secondes à le faire.
    @Test("Une surveillance annulée pendant la relance cesse de sonder au lieu de s'emballer")
    func surveillanceAnnuleePendantLaRelanceNeSEmballePas() async {
        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        double.sondagesAvantApparition[vibe] = .max   // relancée, mais elle n'affiche jamais rien
        _ = double.tuer(pid: 100)

        let bascule = Bascule(controleur: double, intervalleSondage: .milliseconds(10),
                              delaiMax: .seconds(5),  // la valeur du produit
                              trustAccorde: { true }, encocheMesurable: { true })
        let tache = Task { await bascule.poursuivreFermeture(de: info(vibe, .supported, pid: 100),
                                                             puisRelancer: true) }
        // Attendre que la tâche soit VRAIMENT dans la boucle d'apparition : la relance est partie,
        // et le seul point de suspension qui suit est le sommeil de sondage.
        while !double.journal.contains(.lance(vibe)) { await Task.yield() }
        let avant = double.sondagesVisibilite
        tache.cancel()
        _ = await tache.value

        #expect(double.sondagesVisibilite - avant <= 2)
    }
}

// MARK: - Le câblage : ce que `WindowManager` fait des verdicts, enfin atteignable

/// Un `WindowManager` monté sur le double, avec l'encoche et son contenu injectés. C'est la
/// sortie de test qui manquait : sans `scan:`, `apps` reste vide et aucun des deux verdicts
/// « en cours » n'atteint son `case`.
@MainActor
func gestionnaire(
    _ double: ControleurAppsDouble, ecran: EcranSimule, suite: String,
    defaults: UserDefaults, dansLEncoche: [String], bascule: Bascule,
    verifierAccessibilite: (() -> Bool)? = nil
) -> WindowManager {
    WindowManager(
        startTimer: false,
        catalogue: CatalogueApps(defaults: defaults, amorcage: Set(dansLEncoche),
                                 resolveur: { URL(fileURLWithPath: "/Applications/\($0).app") }),
        controleur: double,
        reglages: Reglages(defaults: defaults),
        geometrie: { ecran.geometrie },
        // Ce que le WindowServer montrerait : les apps lancées qu'on n'a pas masquées. Le double
        // est la seule source, donc le modèle ne peut pas diverger du monde qu'il est censé
        // observer — c'est ce qui rend `bundleIDActive` et `isHiddenByUs` significatifs ici.
        scan: { zone, _ in
            dansLEncoche.compactMap { id in
                guard let pid = double.pidsParBundleID[id], !double.masquees.contains(id) else { return nil }
                return (pid: pid, bundleID: id, name: id, cadre: zone)
            }
        },
        // Les pids du double n'appartiennent à aucun vrai process : sans cette seconde moitié de
        // la sortie de test, `recaler` relit toute app masquée comme morte et la sort de la liste.
        processVivant: { pid in double.pidsParBundleID.values.contains(pid) },
        demanderAccessibilite: false,
        verifierAccessibilite: verifierAccessibilite ?? { true },
        bascule: bascule
    )
}

@MainActor
struct CablageSurveillanceTests {

    /// D1 au niveau du câblage. `WindowManager` doit passer la précédente à la surveillance :
    /// sans elle, la relance aboutit et l'encoche en porte deux — ce que le modèle ne sait même
    /// pas, puisqu'il marquait la cible active sans rien dire de l'autre.
    @Test("Câblage : la surveillance range la précédente que la bascule n'a pas pu éteindre")
    func laSurveillanceRangeLaPrecedente() async {
        let suite = "SurveillanceDoublon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(lancees: [boring: 200, vibe: 100], installees: [boring, vibe])
        let ecran = EcranSimule()
        let wm = gestionnaire(
            double, ecran: ecran, suite: suite, defaults: defaults, dansLEncoche: [boring, vibe],
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                             delaiMax: .milliseconds(400), delaiMort: .milliseconds(5),
                             trustAccorde: { true }, encocheMesurable: { ecran.branche })
        )
        // `testSupport` part dans un `Task` depuis `sonder()` : le laisser classer les deux apps.
        while wm.apps.contains(where: { $0.support == .testing }) { await Task.yield() }
        #expect(wm.bundleIDActive == boring)

        double.sondagesAvantApparition[vibe] = 1   // le démasquage ne ramène rien -> repli tuer
        double.sondagesAvantMort[vibe] = 30        // 60 ms, hors des 5 ms de courtoisie

        await wm.basculer(vers: vibe)
        // Le message dit les DEUX moitiés : la relance à venir, et la précédente encore à l'écran.
        #expect(wm.echecBascule?.contains(boring) == true)
        let surveillance = wm.surveillanceFermeture
        #expect(surveillance != nil)
        await surveillance?.value

        #expect(double.pid(pour: vibe) != nil)                        // la cible est rendue
        #expect(double.fenetreVisibleDansNotch(pid: 200) == false)    // et la précédente rangée
        #expect(wm.apps.first { $0.bundleID == boring }?.isHiddenByUs == true)
        #expect(wm.bundleIDActive == vibe)
        #expect(wm.echecBascule == nil)                               // plus rien à signaler
    }

    /// D2 au niveau du câblage : c'est bien le GESTE SUIVANT qui annule, et l'app abandonnée ne
    /// revient pas dans le dos de l'utilisateur.
    ///
    /// Ce que ce test épingle exactement — et il faut le dire, parce que ce n'est pas le garde de
    /// `Bascule` : c'est le `surveillanceFermeture?.cancel()` de `WindowManager.basculer`. Retirer
    /// ces deux lignes le fait échouer (`journal.contains(.lance(vibe)) == true`) ; retirer le
    /// garde de `poursuivreFermeture` ne le fait PAS échouer, parce qu'ici l'annulation arrive
    /// pendant l'attente de mort, moitié du chemin qui était déjà gardée. Le garde neuf, lui, est
    /// épinglé par `surveillanceAnnuleeAvantLaRelanceNeRelancePas`, où l'app est DÉJÀ morte.
    @Test("Câblage : le geste suivant annule la surveillance, l'app abandonnée ne revient pas")
    func leGesteSuivantAnnuleLaSurveillance() async {
        let suite = "SurveillanceDoublon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(lancees: [boring: 200, vibe: 100], installees: [boring, vibe])
        let ecran = EcranSimule()
        let wm = gestionnaire(
            double, ecran: ecran, suite: suite, defaults: defaults, dansLEncoche: [boring, vibe],
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                             delaiMax: .milliseconds(400), delaiMort: .milliseconds(5),
                             trustAccorde: { true }, encocheMesurable: { ecran.branche })
        )
        while wm.apps.contains(where: { $0.support == .testing }) { await Task.yield() }

        double.sondagesAvantApparition[vibe] = 1
        // Assez longue pour que la surveillance soit encore dans sa boucle d'attente de mort
        // quand le geste suivant arrive : 200 sondages de 2 ms, soit 400 ms.
        double.sondagesAvantMort[vibe] = 200

        await wm.basculer(vers: vibe)
        let surveillance = wm.surveillanceFermeture
        #expect(surveillance != nil)

        // Le geste 2 : `WindowManager.basculer` annule la surveillance avant toute autre chose.
        await wm.basculer(vers: boring)
        _ = await surveillance?.value

        #expect(double.journal.contains(.lance(vibe)) == false)
        #expect(wm.surveillanceFermeture == nil)
    }

    /// D3 : l'écran débranché PENDANT la surveillance. La relance est la bonne décision — l'app
    /// tuée est rendue — mais le message doit dire l'encoche absente, pas accuser l'app.
    /// Avant le correctif : « Vibe Island s'est relancée sans rien afficher dans l'encoche »,
    /// c'est-à-dire l'utilisateur qui ferme son capot envoyé déboguer son app.
    @Test("Câblage : l'écran débranché pendant la surveillance n'accuse pas l'app")
    func lEcranDebranchePendantLaSurveillanceNAccusePasLApp() async {
        let suite = "SurveillanceDoublon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let double = ControleurAppsDouble(lancees: [vibe: 100], installees: [vibe])
        let ecran = EcranSimule()
        let wm = gestionnaire(
            double, ecran: ecran, suite: suite, defaults: defaults, dansLEncoche: [vibe],
            bascule: Bascule(controleur: double, intervalleSondage: .milliseconds(2),
                             delaiMax: .milliseconds(40), delaiMort: .milliseconds(5),
                             trustAccorde: { true }, encocheMesurable: { ecran.branche })
        )
        while wm.apps.contains(where: { $0.support == .testing }) { await Task.yield() }

        double.sondagesAvantApparition[vibe] = .max   // rien n'apparaîtra plus : l'encoche s'en va
        double.sondagesAvantMort[vibe] = 30

        await wm.basculer(vers: vibe)
        #expect(wm.surveillanceFermeture != nil)
        // Le capot se ferme MAINTENANT : on tient le main actor, la surveillance n'a pas encore
        // tourné. Les deux mesures partent ensemble, comme sur la vraie machine.
        ecran.branche = false
        double.encocheMesurable = false

        let surveillance = wm.surveillanceFermeture
        await surveillance?.value

        // L'app est bel et bien revenue : c'est ce que la relance sans garde nous doit.
        #expect(double.journal.contains(.lance(vibe)))
        #expect(wm.echecBascule == texte("error.noNotch.relaunchedUnverified", vibe))
    }
}
