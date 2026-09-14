//
// BarreDesMenusTests.swift — la rangée de la barre des menus appartient à quelqu'un d'autre, des
// DEUX côtés du boîtier caméra.
//
// Ce fichier existe parce que le défaut N1 a été corrigé une fois par moitié. T156 (`857d14f`) a
// borné la flèche DROITE contre le bandeau des icônes de statut — le seul obstacle qu'il avait
// mesuré — et n'a jamais regardé la gauche, ni dans le correctif ni dans ses six tests neufs. La
// QA du 2026-09-06 a mesuré l'autre moitié, `kAXMenuBar` en main, Arc au premier plan : les deux
// flèches volaient un titre de menu, à toutes les marges du domaine réglable.
//
// La leçon du dépôt, pour la quatrième fois : une condition géométrique non bornée est un
// demi-plan. Les tests ci-dessous refusent donc de pouvoir passer en ne vérifiant qu'un côté —
// `lesObstaclesCouvrentLesDeuxCotes` échoue si le jeu d'obstacles perd sa moitié gauche ou sa
// moitié droite, et les autres balayent ce jeu en entier.
//

import Foundation
import AppKit
import Testing
@testable import BouncerCore

@Suite("Rien de cliquable dans la rangée de la barre des menus")
struct BarreDesMenusTests {
    // MARK: - Le relevé, machine de référence, 2026-09-06

    /// Écran interne de la machine de référence.
    private let ecran = CGRect(x: 0, y: 0, width: 1352, height: 878)
    /// Boîtier caméra : la zone non affichable du capteur, 593→759, haute de 29 pt (`safeAreaInsets.top`).
    private let boitier = CGRect(x: 593, y: 849, width: 166, height: 29)
    /// Hauteur de la rangée de la barre des menus réservée par macOS (35 pt, mesurée via
    /// `frame.maxY - visibleFrame.maxY`, 34 pt dessinés). Le boîtier caméra ne fait que 29 pt,
    /// mais la rangée s'étend 6 pt plus bas (843→878 au lieu de 849→878).
    private let hauteurRangee: CGFloat = 35
    /// Ordonnée minimale de la rangée de la barre des menus dans le repère de l'écran (878 - 35 = 843).
    private var minYRangee: CGFloat { ecran.maxY - hauteurRangee }
    /// `min(hauteurBande - 4, 22)` — la taille réelle du chevron dans une bande de 29 pt.
    private let taille: CGFloat = 22

    /// Les titres de menus RÉELLEMENT relevés (`kAXMenuBar`), par app au premier plan.
    ///
    /// L'emprise change du simple au double selon l'app — c'est tout le fond du problème, et c'est
    /// pourquoi aucune constante ne peut la borner : Munder Difflin s'arrête à 362, le Finder à
    /// 489, Arc à 819. Arc DÉBORDE le boîtier (593→759) : macOS reprend la pose de ses titres à
    /// droite de la caméra, d'où le second segment. « Window » finit à 584, « Help » va de 768 à
    /// 819 — les deux cibles que les flèches volaient.
    private var titresDeMenus: [(app: String, segments: [CGRect])] {
        func rangee(_ minX: CGFloat, _ maxX: CGFloat) -> CGRect {
            CGRect(x: minX, y: minYRangee, width: maxX - minX, height: hauteurRangee)
        }
        return [
            ("Munder Difflin", [rangee(0, 362)]),
            ("Finder", [rangee(0, 489)]),
            ("Arc", [rangee(0, 584), rangee(768, 819)]),
        ]
    }

    /// Le bandeau des icônes de statut, aligné à droite. Relevé CGWindowList (`layer` 25) ramené
    /// sur l'écran interne : bord gauche à 910.
    private var bandeauStatut: CGRect {
        CGRect(x: 910, y: minYRangee, width: ecran.maxX - 910, height: hauteurRangee)
    }

    /// Tout ce que Bouncer n'a pas le droit de recouvrir, des deux côtés du boîtier.
    private var obstacles: [(quoi: String, cadre: CGRect)] {
        titresDeMenus.flatMap { app, segments in
            segments.map { (quoi: "titres de menus \(app) \(Int($0.minX))→\(Int($0.maxX))", cadre: $0) }
        } + [(quoi: "icônes de statut \(Int(bandeauStatut.minX))→\(Int(bandeauStatut.maxX))",
              cadre: bandeauStatut)]
    }

    // MARK: - Le garde-fou du garde-fou

    /// Le test qui échoue si un seul côté est vérifié.
    ///
    /// Sans lui, retirer Arc du relevé rendrait tous les autres tests verts sans rien corriger —
    /// c'est exactement l'angle mort de T156, dont le jeu de tests ne contenait que le bandeau de
    /// droite. Un obstacle de chaque côté du boîtier, et au moins un qui vient de la gauche.
    @Test func lesObstaclesCouvrentLesDeuxCotes() {
        let aGauche = obstacles.filter { $0.cadre.minX < boitier.minX }
        let aDroite = obstacles.filter { $0.cadre.maxX > boitier.maxX }
        #expect(!aGauche.isEmpty, "plus aucun obstacle à gauche du boîtier : le test ne prouve plus rien")
        #expect(!aDroite.isEmpty, "plus aucun obstacle à droite du boîtier : le test ne prouve plus rien")
        // Et la gauche doit contenir de vrais titres de menus, pas seulement le bord d'écran.
        #expect(aGauche.contains { $0.cadre.maxX > 500 },
                "les titres de menus qui arrivent AU boîtier ont disparu du relevé")
    }

    // MARK: - L'invariant

    /// Aucun contrôle cliquable de Bouncer ne recouvre un titre de menu ni une icône de statut.
    ///
    /// Balayé sur tout le domaine réglable de la marge ET du retrait : ce sont deux curseurs des
    /// réglages, pas des constantes, et le retrait fait SORTIR la flèche de sa marge pendant la
    /// révélation — une borne qui ne le compterait pas serait fausse à mi-course.
    @Test func aucuneFlecheNeRecouvreLaBarreDesMenus() {
        for marge in stride(from: Reglages.Domaine.marge.lowerBound,
                            through: Reglages.Domaine.marge.upperBound, by: 4) {
            for retrait in stride(from: Reglages.Domaine.retrait.lowerBound,
                                  through: Reglages.Domaine.retrait.upperBound, by: 4) {
                for fleche in cadresFlechesEcran(marge: marge, retrait: retrait) {
                    for obstacle in obstacles {
                        #expect(!fleche.intersects(obstacle.cadre),
                                "marge \(marge), retrait \(retrait) : flèche \(fleche) sur \(obstacle.quoi)")
                    }
                }
            }
        }
    }

    /// Le panel lui-même — pas seulement ses boutons — reste hors de la rangée.
    ///
    /// C'est la borne qui n'a pas de côté, et c'est pour ça qu'elle est retenue : `hitTest` ne
    /// laisse passer que les deux boutons, mais un panel posé DANS la rangée reste une fenêtre au
    /// niveau `statusBar + 10` au-dessus de menus qu'on ne voit plus. Une borne en Y ne peut pas
    /// être satisfaite d'un seul côté, là où deux bornes en X demandent de relire `kAXMenuBar` à
    /// chaque activation d'app.
    @Test func lePanelNEntrePasDansLaRangeeDeLaBarreDesMenus() {
        let rangee = CGRect(x: ecran.minX, y: minYRangee, width: ecran.width, height: hauteurRangee)
        for marge in stride(from: Reglages.Domaine.marge.lowerBound,
                            through: Reglages.Domaine.marge.upperBound, by: 4) {
            let panel = bandeFleches(survol: zoneSurvol(encoche: boitier, marge: marge), hauteurRangee: hauteurRangee)
            #expect(!panel.intersects(rangee), "marge \(marge) : panel \(panel) dans la rangée")
            #expect(panel.maxY <= minYRangee)
        }
    }

    /// Ce que le correctif ne doit PAS coûter : les flèches bordent toujours le boîtier.
    ///
    /// L'acquis de T156, qu'on ne perd pas. Calées sur les bornes de la fenêtre d'encoche, elles
    /// atterrissaient à 118 pt dans le bandeau de statut. Elles restent donc collées au boîtier en
    /// X, et à une rangée de lui en Y — assez près pour qu'on les lise comme ses flèches.
    @Test func lesFlechesBordentToujoursLeBoitier() {
        let panel = bandeFleches(survol: zoneSurvol(encoche: boitier, marge: 44), hauteurRangee: hauteurRangee)
        #expect(panel.minY == boitier.minY - hauteurRangee)
        for fleche in cadresFlechesEcran(marge: 44, retrait: 0) {
            #expect(abs(fleche.midY - boitier.minY) <= hauteurRangee,
                    "flèche \(fleche) trop loin du boîtier")
        }
        // Une de chaque côté, jamais les deux du même.
        let x = cadresFlechesEcran(marge: 44, retrait: 0).map(\.midX).sorted()
        #expect(x[0] < boitier.minX)
        #expect(x[1] > boitier.maxX)
    }

    /// La zone écoutée doit contenir la bande des flèches, sinon le panel se retire sous la main
    /// qui va la chercher — et en ancrage « boîtier seul » (`fenetre: nil`) rien d'autre ne
    /// rattraperait la descente.
    @Test func laZoneEcouteeSuitLesFlechesDescendues() {
        let survol = zoneSurvol(encoche: boitier, marge: 44)
        let panel = bandeFleches(survol: survol, hauteurRangee: hauteurRangee)
        for fenetre in [nil, CGRect(x: 306, y: 358, width: 740, height: 520)] as [CGRect?] {
            let zone = zoneSwipe(bande: survol, fenetre: fenetre)
            #expect(zone.contains(CGPoint(x: panel.minX + 1, y: panel.midY)))
            #expect(zone.contains(CGPoint(x: panel.maxX - 1, y: panel.midY)))
            // Et elle couvre toujours la rangée elle-même : c'est là que le geste se pose.
            #expect(zone.contains(CGPoint(x: boitier.midX, y: boitier.midY)))
        }
    }

    /// La mesure système `hauteurBarreDesMenus()` respecte le contrat de rangée réservée :
    /// elle s'adapte à l'écran hôte ou retombe sur la valeur de référence (35 pt).
    @Test func hauteurRangeeSystemeConformeAuReleve() {
        let hauteur = hauteurBarreDesMenus()
        #expect(hauteur >= 24 && hauteur <= 50)
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first {
            let reserve = s.frame.maxY - s.visibleFrame.maxY
            let attendu = reserve > 0 ? reserve : 35
            #expect(hauteur == attendu)
        } else {
            #expect(hauteur == 35)
        }
    }

    // MARK: - Outillage

    /// Les deux cadres de flèches en coordonnées ÉCRAN, retrait de révélation compris.
    ///
    /// Reproduit exactement ce que fait `NotchArrowsView.layoutArrows` : le décalage est signé par
    /// côté, la gauche sort vers la gauche et la droite vers la droite.
    private func cadresFlechesEcran(marge: CGFloat, retrait: CGFloat) -> [CGRect] {
        let panel = bandeFleches(survol: zoneSurvol(encoche: boitier, marge: marge), hauteurRangee: hauteurRangee)
        let cadres = cadresFleches(overlay: panel.size, marge: marge)
        return [
            cadres.gauche.offsetBy(dx: -retrait, dy: 0),
            cadres.droite.offsetBy(dx: retrait, dy: 0),
        ].map { $0.offsetBy(dx: panel.minX, dy: panel.minY) }
    }
}
