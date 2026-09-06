//
// EtatReelTests.swift — les trois endroits où Bouncer croyait son propre récit plutôt que l'écran.
//
// Règle commune, et c'est celle du dépôt : toute API système qui rend un booléen sur une action
// ASYNCHRONE ment. Ce qui vaut n'est jamais le code retour, c'est le recomptage de l'état réel.
// Appliquée ici à trois états qui, chacun, survivaient à ce qu'ils décrivaient :
//   - `isHiddenByUs`, qui restait vrai sur une app que l'utilisateur avait relancée à la main ;
//   - la géométrie de l'encoche, jamais relue quand les écrans changeaient ;
//   - `echecBascule`, que rien n'effaçait — le triangle d'alerte restait allumé pour de bon.
//

import AppKit
import Foundation
import Testing
@testable import BouncerCore

@MainActor
struct EtatReelTests {
    private let vibe = "app.vibeisland.macos"
    private let boring = "theboringteam.boringnotch"

    private func masquee(_ bundleID: String, pid: pid_t?) -> NotchAppInfo {
        NotchAppInfo(bundleID: bundleID, name: bundleID, support: .supported, pid: pid, isHiddenByUs: true)
    }

    /// Une encoche que rien à l'écran ne peut croiser : le sondage tourne pour de vrai (il lit le
    /// vrai `CGWindowList`) mais ne trouve jamais rien, donc `apps` reste vide et le test ne dépend
    /// pas de ce qui tourne sur la machine qui le lance.
    ///
    /// À n'utiliser que pour les deux tests de géométrie. Le scan réel bloque le main actor
    /// pendant quelques millisecondes, et les tests de bascule d'à côté sondent avec un budget de
    /// 50 ms : les affamer les ferait échouer pour une raison qui n'est pas la leur. Partout
    /// ailleurs, une géométrie nulle suffit et ne scanne rien.
    private func encocheIntrouvable(_ nom: String) -> (rect: CGRect, ecran: String, cadre: CGRect) {
        (CGRect(x: -100_000, y: -100_000, width: 1, height: 1), nom,
         CGRect(x: -100_000, y: -100_000, width: 2, height: 2))
    }

    private func manager(
        geometrie: @escaping @MainActor () -> (rect: CGRect, ecran: String, cadre: CGRect)? = { nil }
    ) -> WindowManager {
        let suite = "EtatReelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        return WindowManager(
            startTimer: false,
            // Résolveur qui ne trouve rien : catalogue vide, donc cycle vide et menu vide.
            catalogue: CatalogueApps(defaults: defaults, resolveur: { _ in nil }),
            controleur: ControleurAppsDouble(),
            reglages: Reglages(defaults: defaults),
            geometrie: geometrie,
            demanderAccessibilite: false
        )
    }

    // MARK: - Défaut 3 : une app relancée à la main n'est plus masquée par nous

    @Test("Une app masquée que l'utilisateur relance à la main repasse à isHiddenByUs == false")
    func appRevueDansLEncocheNEstPlusMasquee() {
        // Le Dock, Spotlight ou le Launchpad réactivent l'app : macOS lève `kAXHidden` sans rien
        // dire à Bouncer, et le scan la revoit dans l'encoche. C'est ce constat-là qui commande.
        let recale = WindowManager.recaler(
            [masquee(vibe, pid: 100)], vues: [vibe: 100], processVivant: { _ in true }
        )
        #expect(recale.count == 1)
        #expect(recale[0].isHiddenByUs == false)
        #expect(recale[0].pid == 100)
    }

    @Test("Une app réellement masquée le reste : absente du scan, son drapeau ne bouge pas")
    func appAbsenteDuScanResteMasquee() {
        // La contrepartie indispensable : sans elle, le correctif rendrait tout masquage
        // irréversible en effaçant le seul drapeau qui permet de réafficher l'app.
        let recale = WindowManager.recaler(
            [masquee(vibe, pid: 100)], vues: [:], processVivant: { _ in true }
        )
        #expect(recale[0].isHiddenByUs)
        #expect(recale[0].pid == 100)
    }

    @Test("Une app masquée dont le process est mort n'est plus masquée par personne")
    func appMorteNEstPlusMasquee() {
        let recale = WindowManager.recaler(
            [masquee(vibe, pid: 100)], vues: [:], processVivant: { _ in false }
        )
        #expect(recale[0].pid == nil)
        #expect(recale[0].isHiddenByUs == false)
    }

    @Test("Le recalage ne touche qu'aux apps concernées")
    func recalageNeDeborde() {
        let recale = WindowManager.recaler(
            [masquee(vibe, pid: 100), masquee(boring, pid: 200)],
            vues: [vibe: 100], processVivant: { _ in true }
        )
        #expect(recale[0].isHiddenByUs == false)
        #expect(recale[1].isHiddenByUs)
    }

    // MARK: - Défaut 4 : les écrans changent, la géométrie est relue

    @Test("Un changement de paramètres d'écran fait relire la géométrie de l'encoche")
    func changementDEcransRelitLaGeometrie() {
        // Sur la machine de référence le MacBook n'est pas l'écran principal : brancher ou
        // débrancher un moniteur déplace l'encoche, et jusqu'ici rien ne le disait au manager.
        var ecran = "Écran interne"
        let wm = manager(geometrie: { [self] in encocheIntrouvable(ecran) })
        let avant = wm.lastNotchZoneDescription
        #expect(avant.contains("Écran interne"))

        ecran = "Studio Display"
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(wm.lastNotchZoneDescription != avant)
        #expect(wm.lastNotchZoneDescription.contains("Studio Display"))
    }

    @Test("Une encoche qui disparaît est constatée, pas héritée du tour précédent")
    func encocheDisparueEstConstatee() {
        var branchee = true
        let wm = manager(geometrie: { [self] in branchee ? encocheIntrouvable("Écran interne") : nil })
        #expect(wm.notchZone() != nil)

        branchee = false
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(wm.lastNotchZoneDescription == "Aucune encoche détectée sur cette machine.")
    }

    // MARK: - Défaut 9 : « Rafraîchir » ramène à un état propre

    @Test("Rafraîchir efface le triangle d'alerte")
    func rafraichirEffaceLEchec() {
        let wm = manager()
        // Un cycle sans aucune cible : c'est un échec réel, et celui qui allume le triangle sans
        // rien changer à l'écran — donc exactement celui que l'utilisateur ne peut pas dissiper.
        wm.cycle(forward: true)
        #expect(wm.echecBascule != nil)

        wm.refresh()
        #expect(wm.echecBascule == nil)
    }

    @Test("La boucle de sondage n'efface PAS le message : il doit rester lisible")
    func leSondageNEffacePasLeMessage() {
        // La contrepartie du correctif précédent, et la raison pour laquelle il ne vit pas dans
        // `sonder()` : le sondage repasse toutes les deux secondes. S'il effaçait le message,
        // le triangle s'éteindrait avant que l'utilisateur ait ouvert le menu.
        let wm = manager()
        wm.cycle(forward: true)
        let message = wm.echecBascule
        #expect(message != nil)

        wm.sonder()
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(wm.echecBascule == message)
    }
}
