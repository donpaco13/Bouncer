//
// FlechesEntieresTests.swift — verrouille le défaut le plus visible qu'ait connu le produit : les
// chevrons dessinés à moitié hors du panel, constaté en réel le 2026-09-06 sur le build installé
// (« les flèches sont à moitié coupées, on dirait qu'il y a une limite et qu'on ne peut pas
// afficher des éléments en dessous de cette hauteur »).
//
// Deux tests, parce que le défaut vivait entre les deux. `ZoneSurvolTests` couvrait déjà la
// géométrie et il était vert : le cadre des flèches était juste. Ce qui ne l'était pas, c'est le
// CALQUE, décalé d'une demi-taille par un `anchorPoint` centré sans recalage de `position`. Un
// test qui ne regarde que des CGRect calculés ne peut pas voir ça — il faut mesurer ce qui est
// dessiné, donc construire une vraie vue.
//

import AppKit
import Testing
@testable import BouncerCore

@MainActor
struct FlechesEntieresTests {
    /// La bande réelle de la machine de référence : boîtier 166×29, plus 44 pt de marge de chaque
    /// côté (cf. `ZoneSurvolTests`).
    private let bande = CGSize(width: 254, height: 29)
    private let marge: CGFloat = 44

    @Test func laBandeLogeLeChevronEnEntier() {
        let taille = tailleFleche(hauteurBande: bande.height)
        #expect(taille > 0)
        let cadres = cadresFleches(overlay: bande, marge: marge)
        for cadre in [cadres.gauche, cadres.droite] {
            // La hauteur UTILE allouée au chevron ne descend pas sous sa taille intrinsèque : s'il
            // dépasse la bande, la fenêtre l'écrête, et c'est le défaut du 2026-09-06.
            #expect(cadre.height == taille)
            #expect(cadre.minY >= 0)
            #expect(cadre.maxY <= bande.height)
            #expect(cadre.minX >= 0)
            #expect(cadre.maxX <= bande.width)
        }
    }

    @Test func leChevronDessineResteDansLaBande() {
        let hote = NSView(frame: NSRect(origin: .zero, size: bande))
        hote.wantsLayer = true
        let cadres = cadresFleches(overlay: bande, marge: marge)

        for cadre in [cadres.gauche, cadres.droite] {
            let bouton = NSButton(frame: cadre)
            bouton.wantsLayer = true
            hote.addSubview(bouton)
            guard let calque = bouton.layer else {
                Issue.record("la vue n'a pas de calque, le test ne mesure rien")
                return
            }
            ancreAuCentre(calque, cadreVue: bouton.frame)
            calque.transform = CATransform3DMakeScale(1, 1, 1)

            // `calque.frame`, pas `bouton.frame` : la vue était au bon endroit même quand le
            // dessin ne l'était pas — c'est toute la raison d'être de ce test.
            #expect(calque.frame == cadre)
            #expect(hote.bounds.contains(calque.frame))
        }
    }
}
