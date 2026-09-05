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
    /// La taille RÉELLE des flèches, pas une valeur d'illustration : `NotchOverlay.layoutArrows`
    /// pose `min(bounds.height - 4, 22)`, soit 22 pt dans une bande de 29. Le test perdrait tout
    /// son intérêt s'il validait une dimension que la production n'utilise plus — il a verrouillé
    /// 14 pt pendant le temps où le chevron en faisait déjà 22.
    private let taille: CGFloat = 22

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

    // MARK: - Calage sur la fenêtre réellement posée sur l'encoche
    //
    // Relevé du 2026-09-05 sur la machine de référence : boringNotch pose un conteneur de
    // 640×210 pt et Vibe Island un de 740×520, quand le boîtier caméra en fait 166×29. C'est
    // l'écart que ces tests verrouillent — il est la cause mesurée des swipes ratés.

    /// Vibe Island ramené dans le repère de test (boîtier à 593→759) : 740 pt centrés sur le
    /// boîtier, descendant 520 pt sous le bord haut de l'écran.
    private var ile: CGRect { CGRect(x: 306, y: 358, width: 740, height: 520) }
    private var ecran: CGRect { CGRect(x: 0, y: 0, width: 1352, height: 878) }

    @Test func sansFenetreDEncocheLaGeometrieNeBougePas() {
        let cadre = cadreFleches(encoche: boitier, marge: marge, fenetre: nil, ecran: ecran)
        #expect(cadre == zoneSurvol(encoche: boitier, marge: marge))
        #expect(zoneSwipe(cadreFleches: cadre, fenetre: nil) == cadre.insetBy(dx: 0, dy: -6))
    }

    @Test func leCadreDesFlechesEncadreLaFenetreDEncoche() {
        let cadre = cadreFleches(encoche: boitier, marge: marge, fenetre: ile, ecran: ecran)
        #expect(cadre.minX == ile.minX - marge)
        #expect(cadre.maxX == ile.maxX + marge)
        // La HAUTEUR reste celle de la barre des menus : le panel est une vraie fenêtre, lui
        // donner les 520 pt de l'île la ferait recouvrir un tiers de l'écran pour deux chevrons.
        #expect(cadre.minY == boitier.minY)
        #expect(cadre.height == boitier.height)
    }

    @Test func lesFlechesNeSontJamaisPoseesSurLaFenetreDEncoche() {
        // C'est ce qui rend la pastille sombre inutile : le contraste redevient celui de la barre
        // des menus, parce qu'il n'y a plus de surface tierce sous le chevron.
        let cadre = cadreFleches(encoche: boitier, marge: marge, fenetre: ile, ecran: ecran)
        let x = abscissesFleches(largeurOverlay: cadre.width, marge: marge, taille: taille)
        #expect(cadre.minX + x.gauche + taille <= ile.minX)
        #expect(cadre.minX + x.droite >= ile.maxX)
    }

    @Test func laZoneEcouteeCouvreTouteLIleVisible() {
        // Le geste que François posait sur l'île — 180 pt à droite de l'ancienne bande, ou 80 pt
        // sous la barre des menus — tombait par le garde `horsZone`, quand il tombait quelque part.
        let cadre = cadreFleches(encoche: boitier, marge: marge, fenetre: ile, ecran: ecran)
        let zone = zoneSwipe(cadreFleches: cadre, fenetre: ile)
        #expect(zone.contains(CGPoint(x: ile.maxX - 10, y: boitier.midY)))
        #expect(zone.contains(CGPoint(x: boitier.midX, y: boitier.minY - 80)))
        #expect(zone.contains(CGPoint(x: boitier.midX, y: ile.minY + 1)))
        // Et elle ne déborde pas au-delà : la marge des flèches de chaque côté, rien de plus.
        #expect(zone.minX == cadre.minX)
        #expect(!zone.contains(CGPoint(x: cadre.minX - 1, y: boitier.midY)))
    }

    @Test func leCadreNeSortJamaisDeLEcran() {
        // Une app d'encoche large sur un écran étroit pousserait les flèches hors champ.
        let large = CGRect(x: 10, y: 358, width: 1330, height: 200)
        let cadre = cadreFleches(encoche: boitier, marge: marge, fenetre: large, ecran: ecran)
        #expect(cadre.minX >= ecran.minX)
        #expect(cadre.maxX <= ecran.maxX)
    }
}
