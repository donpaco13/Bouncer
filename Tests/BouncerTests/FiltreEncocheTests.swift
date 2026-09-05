//
// FiltreEncocheTests.swift — le filtre qui décide « ceci est une app d'encoche », verrouillé sur
// des mesures et non sur des cas inventés.
//
// Tous les nombres ci-dessous sont des relevés `CGWindowListCopyWindowInfo` faits sur le MacBook de
// référence (écran interne 1352×878 posé à droite d'un écran externe 2560×1440, `screens[0]` étant
// l'externe). Boîtier caméra relevé de 1212 à 1378 en x, sur 29 pt de haut. Les deux dernières
// entrées sont les intrus qu'on a pu reproduire : Discord et une fenêtre Finder poussées le plus
// haut possible sur l'écran interne s'arrêtent à 35 pt du bord, plafonnées par la barre de menus.

import CoreGraphics
import Testing

@testable import BouncerCore

/// Repère `CGWindowList` (origine en haut à gauche de `screens[0]`), tel que l'API le rend.
private func bounds(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> [String: CGFloat] {
    ["X": x, "Y": y, "Width": w, "Height": h]
}

@Suite("Filtre d'encoche — départager une app d'encoche d'une fenêtre qui l'effleure")
struct FiltreEncocheTests {
    private let hauteurEcranPrincipal: CGFloat = 1440
    private let cadreEcran = CGRect(x: 619, y: -878, width: 1352, height: 878)
    private let zone = CGRect(x: 1212, y: -29, width: 166, height: 29)

    private func accepte(_ b: [String: CGFloat]) -> Bool {
        estFenetreEncoche(zone, cadreEcran: cadreEcran, bounds: b, hauteurEcranPrincipal: hauteurEcranPrincipal)
    }

    @Test("Vibe Island passe : 740 pt collés au bord haut, boîtier recouvert de 925 à 1665")
    func vibeIsland() {
        #expect(accepte(bounds(x: 925, y: 1440, w: 740, h: 520)))
    }

    @Test("boringNotch passe : 640 pt collés au bord haut, boîtier recouvert de 975 à 1615")
    func boringNotch() {
        #expect(accepte(bounds(x: 975, y: 1440, w: 640, h: 210)))
    }

    @Test("Un overlay plein écran est recalé — il est collé au bord haut et recouvre le boîtier")
    func overlayPleinEcran() {
        // Le Dock (1352×878) et l'overlay de capture d'écran ont exactement ce profil : ils
        // passeraient les deux premières conditions. Seule la largeur les sépare des vraies.
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 878)) == false)
    }

    @Test("La barre de menus est recalée pour la même raison : toute la largeur de l'écran")
    func barreDeMenus() {
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 34)) == false)
    }

    @Test("La plus large icône de barre de menus relevée (146 pt) ne contient pas un boîtier de 166")
    func iconeDeBarreDeMenus() {
        // Posée volontairement à cheval sur le boîtier, ce que macOS ne fait jamais : même là,
        // elle ne le recouvre pas en entier. C'est ce que verrouille la deuxième condition.
        #expect(accepte(bounds(x: 1250, y: 1440, w: 146, h: 34)) == false)
    }

    @Test("Discord poussé le plus haut possible reste 35 pt sous le bord : recalé")
    func discordEnHautDeLEcran() {
        #expect(accepte(bounds(x: 900, y: 1475, w: 700, h: 500)) == false)
    }

    @Test("Une fenêtre Finder poussée le plus haut possible : recalée pour la même raison")
    func finderEnHautDeLEcran() {
        #expect(accepte(bounds(x: 900, y: 1475, w: 800, h: 360)) == false)
    }

    @Test("Une fenêtre décalée qui n'effleure le boîtier que par un bord est recalée")
    func fenetreQuiEffleure() {
        // 600 pt collés au bord haut, posés de 700 à 1300 : elle mord sur le boîtier (1212→1378)
        // sans le contenir. C'était exactement ce que l'ancien `intersects` laissait passer.
        #expect(accepte(bounds(x: 700, y: 1440, w: 600, h: 300)) == false)
    }
}
