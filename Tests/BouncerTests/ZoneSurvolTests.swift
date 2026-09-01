//
// ZoneSurvolTests.swift — verrouille l'invariant qui a coûté un soir de débogage : les flèches
// tombaient pile derrière le boîtier caméra, donc invisibles, et la zone sensible se limitait à
// cette même bande impossible à viser au curseur. Le test travaille sur la géométrie réellement
// mesurée sur la machine de référence (écran 1352×878, boîtier 593→759).
//

import Foundation
import Testing
@testable import BouncerCore

struct ZoneSurvolTests {
    private let boitier = CGRect(x: 593, y: 849, width: 166, height: 29)
    private let marge: CGFloat = 44
    private let taille: CGFloat = 14

    @Test func laZoneDeSurvolDebordeLeBoitierDesDeuxCotes() {
        let zone = zoneSurvol(encoche: boitier, marge: marge)
        #expect(zone.minX == boitier.minX - marge)
        #expect(zone.maxX == boitier.maxX + marge)
        // La hauteur ne bouge pas : elle vaut déjà toute la bande de barre des menus.
        #expect(zone.minY == boitier.minY)
        #expect(zone.height == boitier.height)
    }

    @Test func lesFlechesTombentEnDehorsDuBoitier() {
        let zone = zoneSurvol(encoche: boitier, marge: marge)
        let x = abscissesFleches(largeurOverlay: zone.width, marge: marge, taille: taille)

        // Repassées en coordonnées écran, les deux flèches doivent être entièrement dans les aires
        // auxiliaires — à gauche de 593 pour l'une, à droite de 759 pour l'autre.
        #expect(zone.minX + x.gauche + taille <= boitier.minX)
        #expect(zone.minX + x.droite >= boitier.maxX)
    }

    @Test func lesFlechesSontCentreesDansLeurMarge() {
        let zone = zoneSurvol(encoche: boitier, marge: marge)
        let x = abscissesFleches(largeurOverlay: zone.width, marge: marge, taille: taille)
        #expect(x.gauche == (marge - taille) / 2)
        #expect(zone.width - (x.droite + taille) == (marge - taille) / 2)
    }
}
