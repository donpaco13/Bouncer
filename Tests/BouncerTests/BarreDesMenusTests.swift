//
// BarreDesMenusTests.swift — la rangée de la barre des menus appartient à quelqu'un d'autre, des
// DEUX côtés du boîtier caméra : l'emprise des titres de menus change avec l'app au premier plan
// (relevé `kAXMenuBar` du 2026-09-06 : Arc pose « Window » et « Help » contre le boîtier).
//
// Les flèches vivent pourtant dans cette rangée. Ce qui le permet, c'est que le panel n'y prend
// AUCUN clic : il ignore la souris. C'est l'invariant que ce fichier verrouille — une borne sans
// côté, valable pour n'importe quelle app, sans rien relire.
//

import Foundation
import AppKit
import Testing
@testable import BouncerCore

@Suite("Rien de cliquable dans la rangée de la barre des menus")
@MainActor
struct BarreDesMenusTests {
    /// Boîtier caméra de la machine de référence : 593→759, haut de 29 pt (`safeAreaInsets.top`).
    private let boitier = CGRect(x: 593, y: 849, width: 166, height: 29)

    /// L'invariant : le panel des flèches ne prend aucun événement souris, sur tout le domaine
    /// réglable de la marge. Et il reste conforme à CLAUDE.md : non activant, au-dessus de la barre.
    @Test func lePanelNaAucuneCibleDeClic() {
        for marge in stride(from: Reglages.Domaine.marge.lowerBound,
                            through: Reglages.Domaine.marge.upperBound, by: 4) {
            let panel = panelFleches(cadre: zoneSurvol(encoche: boitier, marge: marge))
            #expect(panel.ignoresMouseEvents, "marge \(marge) : le panel prendrait des clics")
            #expect(panel.styleMask.contains(.nonactivatingPanel))
            #expect(panel.level.rawValue > NSWindow.Level.statusBar.rawValue)
            #expect(panel.frame == zoneSurvol(encoche: boitier, marge: marge))
        }
    }

    /// Les flèches sont dans la rangée, à hauteur de l'encoche, une de chaque côté du boîtier.
    @Test func lesFlechesBordentLeBoitierDansLaRangee() {
        let bande = zoneSurvol(encoche: boitier, marge: 44)
        let cadres = cadresFleches(overlay: bande.size, marge: 44)
        let fleches = [cadres.gauche, cadres.droite].map { $0.offsetBy(dx: bande.minX, dy: bande.minY) }
        for fleche in fleches {
            #expect(fleche.minY >= boitier.minY && fleche.maxY <= boitier.maxY,
                    "flèche \(fleche) hors de la hauteur de l'encoche")
            #expect(!fleche.intersects(boitier), "flèche \(fleche) cachée par le boîtier")
        }
        #expect(fleches[0].maxX <= boitier.minX)
        #expect(fleches[1].minX >= boitier.maxX)
    }

    /// La zone écoutée contient la bande des flèches, avec ou sans app d'encoche : sinon le panel
    /// se retirerait sous le curseur qui la survole.
    @Test func laZoneEcouteeCouvreLaBandeDesFleches() {
        let bande = zoneSurvol(encoche: boitier, marge: 44)
        for fenetre in [nil, CGRect(x: 306, y: 358, width: 740, height: 520)] as [CGRect?] {
            let zone = zoneSwipe(bande: bande, fenetre: fenetre)
            #expect(zone.contains(CGPoint(x: bande.minX + 1, y: bande.midY)))
            #expect(zone.contains(CGPoint(x: bande.maxX - 1, y: bande.midY)))
            #expect(zone.contains(CGPoint(x: boitier.midX, y: boitier.midY)))
        }
    }
}
