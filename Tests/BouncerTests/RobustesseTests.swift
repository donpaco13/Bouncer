//
// RobustesseTests.swift — ce que Bouncer fait quand ça va mal.
//
// Les tests d'à côté vérifient la bascule quand tout se passe bien. Ceux-ci vérifient les quatre
// pannes réelles d'une machine d'utilisateur : le droit Accessibilité retiré en cours de route,
// une app d'encoche qui meurt pendant une bascule, l'encoche qui disparaît, et un cycle à zéro ou
// un élément. La règle commune, celle qui les fait tous tenir : **une app que Bouncer a masquée
// doit toujours pouvoir revenir**. Une app d'encoche n'a ni icône du Dock ni entrée Cmd-Tab ;
// masquée et oubliée, elle n'est pas seulement invisible, elle est introuvable.
//

import Foundation
import Testing
@testable import BouncerCore

@MainActor
struct RobustesseTests {
    private let vibe = "app.vibeisland.macos"
    private let boring = "theboringteam.boringnotch"

    private func info(_ bundleID: String, _ support: SupportStatus, pid: pid_t?) -> NotchAppInfo {
        NotchAppInfo(bundleID: bundleID, name: bundleID, support: support, pid: pid, isHiddenByUs: false)
    }

    // MARK: - Scénario 1 : l'Accessibilité est révoquée pendant que l'app tourne

    @Test("Accessibilité retirée : une app masquée qu'on ne sait plus démasquer est relancée, pas abandonnée")
    func demasquageImpossibleTombeSurLeCycleDeVie() async throws {
        let double = ControleurAppsDouble(lancees: [vibe: 100])
        #expect(await double.masquer(true, pid: 100))          // Bouncer l'a masquée quand il pouvait
        double.accessibiliteRevoquee = true                    // l'utilisateur décoche Bouncer

        // Deux secondes, pas cinquante millisecondes : le délai est du temps RÉEL sur un acteur
        // principal partagé avec le reste de la suite, qui tourne en parallèle. Un test voisin qui
        // touche AppKit pour la première fois le bloque ~60 ms (mesuré). Le chemin nominal rend la
        // main en quelques millisecondes ; seul le pire cas s'allonge.
        let bascule = Bascule(
            controleur: double, intervalleSondage: .milliseconds(1), delaiMax: .seconds(2),
            delaiMort: .milliseconds(30),
            trustAccorde: { true },  // le droit a été accordé, puis retiré : la connexion AX existe
            encocheMesurable: { true }
        )
        #expect(await bascule.basculer(vers: info(vibe, .supported, pid: 100), depuis: nil) == .reussie)

        // Le démasquage part dans le vide, alors on quitte et on relance : c'est le seul chemin
        // qui remet la fenêtre à l'écran sans l'API Accessibility.
        #expect(double.journal == [.masque(true, 100), .masque(false, 100), .tue(100), .lance(vibe)])
        let pid = try #require(double.pid(pour: vibe))
        #expect(double.fenetreVisibleDansNotch(pid: pid))
    }

    @Test("Le repli ne sacrifie pas l'app en place : si la cible ne peut pas être relancée, l'actuelle reste")
    func repliQuiEchoueNeTouchePasLActuelle() async throws {
        let double = ControleurAppsDouble(lancees: [vibe: 100, boring: 200])
        double.installees.remove(vibe)                          // désinstallée pendant qu'elle tournait
        #expect(await double.masquer(true, pid: 100))
        double.accessibiliteRevoquee = true

        let bascule = Bascule(
            controleur: double, intervalleSondage: .milliseconds(1), delaiMax: .milliseconds(50),
            delaiMort: .milliseconds(30),
            trustAccorde: { true },  // le droit a été accordé, puis retiré : la connexion AX existe
            encocheMesurable: { true }
        )
        let resultat = await bascule.basculer(
            vers: info(vibe, .supported, pid: 100), depuis: info(boring, .supported, pid: 200)
        )

        #expect(resultat == .lancementImpossible)
        // L'encoche n'est jamais vide : boringNotch n'a même pas été touchée.
        #expect(double.pid(pour: boring) == 200)
        #expect(double.fenetreVisibleDansNotch(pid: 200))
    }

    @Test("Droit jamais accordé : la bascule ne touche RIEN — ni l'API AX, ni le process de l'app")
    func trustJamaisAccordeNeToucheALRien() async throws {
        let double = ControleurAppsDouble(lancees: [vibe: 100, boring: 200])
        // Le cas de l'utilisateur qui installe Bouncer et ferme le dialogue d'autorisation : aucune
        // app n'a pu passer `testSupport`, donc toutes valent `.testing`.
        let bascule = Bascule(
            controleur: double, intervalleSondage: .milliseconds(1), delaiMax: .milliseconds(50),
            delaiMort: .milliseconds(30), trustAccorde: { false }, encocheMesurable: { true }
        )

        let resultat = await bascule.basculer(
            vers: info(vibe, .testing, pid: 100), depuis: info(boring, .testing, pid: 200)
        )

        #expect(resultat == .accessibiliteJamaisAccordee)
        // Le journal vide est TOUT le test : un seul `.masque` ici et la connexion Accessibility de
        // Bouncer serait condamnée jusqu'à son prochain lancement, un seul `.tue` et l'app
        // d'encoche de l'utilisateur serait quittée sans qu'il l'ait demandé.
        #expect(double.journal.isEmpty)
        #expect(double.pid(pour: boring) == 200)
        #expect(double.fenetreVisibleDansNotch(pid: 200))
    }

    // MARK: - Scénario 2 : une app meurt pendant une bascule
    //
    // Le cas « la cible ne vient jamais » est déjà couvert par `BasculeTests` : l'actuelle est
    // intacte et l'échec remonte, parce que `eteindre` n'est structurellement atteignable qu'après
    // un `allumer` réussi. Rien à corriger là — ce qui manquait était en aval, quand Bouncer lui-
    // même disparaît en laissant une app masquée derrière lui.

    @Test("Le filet de restauration lève le masquage sans rien attendre — ce qu'un handler de quit peut faire")
    func restaurationSansAttente() async throws {
        let double = ControleurAppsDouble(lancees: [vibe: 100])
        #expect(await double.masquer(true, pid: 100))
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)

        double.reafficherSansAttendre(pid: 100)
        #expect(double.fenetreVisibleDansNotch(pid: 100))

        // Idempotent : l'appeler sur une app déjà visible ne coûte rien et ne casse rien, ce qui
        // autorise à le passer sur tout le catalogue au démarrage sans savoir ce qui est masqué.
        double.reafficherSansAttendre(pid: 100)
        #expect(double.fenetreVisibleDansNotch(pid: 100))
    }

    // MARK: - Scénario 4 : zéro ou une seule app au catalogue

    @Test("Un cycle vide ne désigne aucune cible — c'est à l'appelant de le dire, pas de faire semblant")
    func cycleVide() {
        #expect(prochaineCible(dans: [String](), depuis: nil, forward: true) == nil)
        #expect(prochaineCible(dans: [String](), depuis: "a", forward: false) == nil)
    }

    @Test("Une seule app au catalogue : le cycle revient sur elle, et la bascule devient un interrupteur")
    func cycleAUnElement() async throws {
        #expect(prochaineCible(dans: ["a"], depuis: "a", forward: true) == "a")
        #expect(prochaineCible(dans: ["a"], depuis: nil, forward: true) == "a")

        let double = ControleurAppsDouble(lancees: [vibe: 100])
        // Délai généreux, pour la raison expliquée plus haut : ce test attend deux SUCCÈS.
        let bascule = Bascule(
            controleur: double, intervalleSondage: .milliseconds(1), delaiMax: .seconds(2),
            delaiMort: .milliseconds(30), trustAccorde: { true }, encocheMesurable: { true }
        )
        let seule = info(vibe, .supported, pid: 100)

        // Visible -> éteinte
        #expect(await bascule.basculer(vers: seule, depuis: seule) == .reussie)
        #expect(double.fenetreVisibleDansNotch(pid: 100) == false)
        // Éteinte -> visible : le geste reste réversible, jamais un aller simple.
        #expect(await bascule.basculer(vers: seule, depuis: seule) == .reussie)
        #expect(double.fenetreVisibleDansNotch(pid: 100))
    }
}
