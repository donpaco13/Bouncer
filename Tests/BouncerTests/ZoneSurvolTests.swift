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

    // MARK: - Bandeau des icônes de statut
    //
    // Relevé CGWindowList du 2026-09-05 (`layer` 25, écran 2560×1440 de la machine) : Hidden Bar,
    // CopyClip, Bouncer, Vorssaint, One Thing et le Centre de contrôle occupent 2112→2560, soit
    // les 448 pt les plus à DROITE de la barre des menus. Ramené sur l'écran interne 1352 du
    // repère de test, le bord gauche du bandeau tombe donc à 904.
    //
    // Ce que ces deux tests interdisent de revenir : les flèches calées sur les bornes de la
    // fenêtre d'encoche se logeaient à 1025→1047, soit 118 pt DEDANS, et volaient le clic de
    // Vorssaint (le panel vit au niveau `statusBar + 10`, au-dessus des icônes).

    /// Le bandeau des icônes de statut, mesuré. Aligné à droite de l'écran.
    private var bandeauStatut: CGRect {
        CGRect(x: ecran.maxX - 448, y: boitier.minY, width: 448, height: boitier.height)
    }

    @Test func lesFlechesTombentHorsDuBandeauDesIconesDeStatut() {
        // Sur tout le domaine réglable de la marge : c'est un curseur dans les réglages, pas une
        // constante, et le dégagement doit tenir à ses deux bouts.
        for marge in stride(from: CGFloat(24), through: 96, by: 4) {
            let bande = zoneSurvol(encoche: boitier, marge: marge)
            let x = abscissesFleches(largeurOverlay: bande.width, marge: marge, taille: taille)
            let droite = CGRect(x: bande.minX + x.droite, y: bande.minY,
                                width: taille, height: bande.height)
            #expect(!droite.intersects(bandeauStatut), "marge \(marge) : flèche droite \(droite)")
        }
    }

    @Test func laBandeDesFlechesNeSuitPasLaFenetreDEncoche() {
        // La régression tenait entièrement là : la bande passait de 254 à 768 pt de barre des
        // menus, et c'est ce qui emmenait les chevrons dans le bandeau. Elle ne dépend plus que
        // du boîtier et de la marge.
        let bande = zoneSurvol(encoche: boitier, marge: marge)
        #expect(bande.width == boitier.width + 2 * marge)
        #expect(bande.maxX + taille <= bandeauStatut.minX)
    }

    // MARK: - Zone écoutée : large en X, bornée en Y
    //
    // Relevé du 2026-09-05 sur la machine de référence : boringNotch pose un conteneur de
    // 640×210 pt et Vibe Island un de 740×520, quand le boîtier caméra en fait 166×29. C'est
    // l'écart qui rendait le geste introuvable. Mais la fenêtre n'est pas l'île : capture de la
    // région exacte du canevas de boringNotch (640×210) — pas un pixel dessiné. Écouter toute sa
    // hauteur portait la zone à 38,5 % de l'écran, où un défilement horizontal ordinaire bascule.

    /// Vibe Island ramené dans le repère de test (boîtier à 593→759) : 740 pt centrés sur le
    /// boîtier, descendant 520 pt sous le bord haut de l'écran.
    private var ile: CGRect { CGRect(x: 306, y: 358, width: 740, height: 520) }
    private var ecran: CGRect { CGRect(x: 0, y: 0, width: 1352, height: 878) }

    @Test func sansFenetreDEncocheLaGeometrieNeBougePas() {
        let bande = zoneSurvol(encoche: boitier, marge: marge)
        #expect(zoneSwipe(bande: bande, fenetre: nil) == bande.insetBy(dx: 0, dy: -6))
    }

    @Test func laZoneEcouteeCouvreLesDeuxGestesMesures() {
        // Les deux gestes que François posait et que Bouncer ratait, relevés le 2026-09-05.
        let zone = zoneSwipe(bande: zoneSurvol(encoche: boitier, marge: marge), fenetre: ile)
        // 180 pt à droite de l'ancienne bande de 254 pt.
        #expect(zone.contains(CGPoint(x: boitier.maxX + marge + 180, y: boitier.midY)))
        // 80 pt sous la barre des menus.
        #expect(zone.contains(CGPoint(x: boitier.midX, y: boitier.minY - 80)))
        // Et toute la largeur de l'île, qui est ce que l'utilisateur voit et vise.
        #expect(zone.contains(CGPoint(x: ile.maxX - 10, y: boitier.midY)))
        #expect(zone.contains(CGPoint(x: ile.minX + 10, y: boitier.midY)))
    }

    @Test func laZoneEcouteeNeDescendPasJusquEnBasDeLIleDeployee() {
        // La régression : 868×526 = 38,5 % de l'écran interne. Un défilement horizontal ORDINAIRE
        // y suffisait — rejeu mesuré, 40 événements de −12 pt en X, une bascule.
        let zone = zoneSwipe(bande: zoneSurvol(encoche: boitier, marge: marge), fenetre: ile)
        let part = (zone.width * zone.height) / (ecran.width * ecran.height)
        #expect(part < 0.12, "la zone occupe \(Int(part * 100)) % de l'écran")
        // Le bas de l'île déployée n'est plus écouté : c'est là que vivent les contenus qui
        // défilent horizontalement, pas le geste d'encoche.
        #expect(!zone.contains(CGPoint(x: boitier.midX, y: ile.minY + 1)))
        #expect(!zone.contains(CGPoint(x: boitier.midX, y: ecran.maxY - 300)))
    }

    @Test func unDefilementHorizontalOrdinaireDansLeTiersHautNeBasculePlus() {
        // Rejeu du flux exact du rapport de QA : 40 événements de −12 pt en X et −2 en Y, curseur
        // à 300 pt du haut de l'écran, là où l'utilisateur fait défiler un tableau ou un carrousel.
        let zone = zoneSwipe(bande: zoneSurvol(encoche: boitier, marge: marge), fenetre: ile)
        #expect(basculesDuDefilement(curseur: CGPoint(x: boitier.midX, y: ecran.maxY - 300),
                                     zone: zone) == 0)
        // Le même flux posé là où le geste d'encoche se fait, lui, bascule toujours une fois.
        #expect(basculesDuDefilement(curseur: CGPoint(x: boitier.midX, y: boitier.minY - 80),
                                     zone: zone) == 1)
    }

    /// Le flux mesuré du rapport de QA, rejoué à travers le détecteur de production.
    private func basculesDuDefilement(curseur: CGPoint, zone: CGRect) -> Int {
        var detecteur = DetecteurSwipe()
        var n = 0
        var t = 0.0
        func envoie(_ phase: EvenementDefilement.Phase, _ dx: CGFloat, _ dy: CGFloat) {
            let d = detecteur.recoit(EvenementDefilement(
                phase: phase, inertie: false, deltaX: dx, deltaY: dy,
                instant: t, dansLaZone: zone.contains(curseur)))
            if d == .bascule { n += 1 }
            t += 0.016
        }
        envoie(.debut, 0, 0)
        for _ in 0..<40 { envoie(.encours, -12, -2) }
        envoie(.fin, 0, 0)
        return n
    }

    @Test func laZoneEcouteeNeDebordeJamaisLaFenetre() {
        // Elle suit l'île en largeur, elle ne l'élargit pas : la bande des flèches est plus
        // étroite que l'île, donc c'est l'île qui borne.
        let zone = zoneSwipe(bande: zoneSurvol(encoche: boitier, marge: marge), fenetre: ile)
        #expect(zone.minX == ile.minX)
        #expect(zone.maxX == ile.maxX)
    }
}
