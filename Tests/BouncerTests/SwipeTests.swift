//
// SwipeTests.swift — verrouille le correctif du 2026-09-03 : un geste physique, une bascule.
//
// Le flux de référence n'est pas inventé, il est ENREGISTRÉ : un geste complet capturé le
// 2026-09-03 à travers le même monitor global `.scrollWheel` que l'app, curseur dans la bande
// d'encoche — 14 événements de geste (Σ deltaX = -77) puis 72 d'inertie sur 1,32 s
// (Σ deltaX = -128). Rejoué dans l'ancienne règle, il produisait DEUX bascules ; c'est ce
// doublon que ces tests interdisent de revenir.
//

import Foundation
import Testing
@testable import BouncerCore

struct SwipeTests {
    /// Reconstitue le flux mesuré : rampe du geste, puis traîne d'inertie décroissante.
    private func gesteEnregistre(versLaGauche: Bool = true, dansLaZone: Bool = true)
        -> [EvenementDefilement]
    {
        let signe: CGFloat = versLaGauche ? -1 : 1
        var flux: [EvenementDefilement] = []
        var t = 0.0
        func ajoute(_ phase: EvenementDefilement.Phase, _ inertie: Bool, _ dx: CGFloat) {
            flux.append(EvenementDefilement(phase: phase, inertie: inertie, deltaX: dx, deltaY: 0,
                                            instant: t, dansLaZone: dansLaZone))
            t += 0.016
        }
        ajoute(.debut, false, 0)
        for i in 0..<14 { ajoute(.encours, false, signe * min(8, 1 + CGFloat(i) * 0.9)) }
        ajoute(.fin, false, 0)
        var amp: CGFloat = 7
        for _ in 0..<71 { amp *= 0.96; ajoute(.encours, true, signe * amp) }
        return flux
    }

    /// Nombre de bascules produites par le flux. Un compte et non une liste de sens : la
    /// décision n'en porte plus, le swipe avance d'un cran dans les deux sens.
    private func bascules(_ flux: [EvenementDefilement], _ detecteur: DetecteurSwipe = .init())
        -> Int
    {
        var d = detecteur
        return flux.filter { d.recoit($0) == .bascule }.count
    }

    @Test("Un geste physique complet, inertie comprise, ne produit qu'UNE bascule")
    func unGesteUneBascule() {
        #expect(bascules(gesteEnregistre()) == 1)
    }

    @Test("Vers la droite : une bascule aussi, et du même côté du cycle")
    func sensInverse() {
        // Le geste inverse produit exactement la même décision que le geste direct : c'est ça,
        // « un seul côté suffit ». Rien dans la décision ne distingue plus les deux sens.
        #expect(bascules(gesteEnregistre(versLaGauche: false)) == 1)
        #expect(bascules(gesteEnregistre(versLaGauche: false)) == bascules(gesteEnregistre()))
    }

    @Test("La traîne d'inertie seule ne déclenche jamais rien")
    func inertieSeule() {
        let inertie = gesteEnregistre().filter(\.inertie)
        #expect(inertie.count > 60)  // le flux mesuré en contenait 72
        #expect(bascules(inertie) == 0)
    }

    @Test("Deux gestes successifs produisent deux bascules, même rapprochés")
    func deuxGestes() {
        // Le cooldown de 0,5 s mangeait le second geste volontaire ; la détente par geste, non.
        var flux = gesteEnregistre()
        let fin = flux.last!.instant + 0.05
        flux += gesteEnregistre().map {
            EvenementDefilement(phase: $0.phase, inertie: $0.inertie, deltaX: $0.deltaX,
                                deltaY: $0.deltaY, instant: $0.instant + fin,
                                dansLaZone: $0.dansLaZone)
        }
        #expect(bascules(flux) == 2)
    }

    @Test("Deux gestes lents sous le seuil ne s'additionnent pas d'un geste à l'autre")
    func pasDeReportEntreGestes() {
        var d = DetecteurSwipe()
        var decisions: [DetecteurSwipe.Decision] = []
        for tour in 0..<2 {
            let base = Double(tour)
            decisions.append(d.recoit(.init(phase: .debut, inertie: false, deltaX: 0, deltaY: 0,
                                            instant: base, dansLaZone: true)))
            decisions.append(d.recoit(.init(phase: .encours, inertie: false, deltaX: -4, deltaY: 0,
                                            instant: base + 0.01, dansLaZone: true)))
            decisions.append(d.recoit(.init(phase: .fin, inertie: false, deltaX: 0, deltaY: 0,
                                            instant: base + 0.02, dansLaZone: true)))
        }
        #expect(decisions.allSatisfy { $0 == .rien })
    }

    @Test("Un défilement vertical qui dérive un peu sur le côté ne bascule pas")
    func dominanceHorizontale() {
        var flux: [EvenementDefilement] = [
            .init(phase: .debut, inertie: false, deltaX: 0, deltaY: 0, instant: 0, dansLaZone: true)
        ]
        for i in 0..<20 {
            flux.append(.init(phase: .encours, inertie: false, deltaX: -1, deltaY: -9,
                              instant: 0.016 * Double(i + 1), dansLaZone: true))
        }
        #expect(bascules(flux) == 0)
    }

    @Test("Curseur hors de la zone : rien ne passe")
    func horsZone() {
        #expect(bascules(gesteEnregistre(dansLaZone: false)) == 0)
    }

    @Test("Molette classique (aucune phase) : la fenêtre de repos reste le seul anti-rebond")
    func moletteSansPhase() {
        var flux: [EvenementDefilement] = []
        for i in 0..<12 {
            flux.append(.init(phase: .aucune, inertie: false, deltaX: -10, deltaY: 0,
                              instant: 0.05 * Double(i), dansLaZone: true))
        }
        // 12 crans sur 0,55 s : la fenêtre de repos de 0,5 s en laisse passer deux, pas douze.
        #expect(bascules(flux) == 2)
    }

    @Test("L'opacité des flèches suit la distance à la zone")
    func rampeDApproche() {
        let zone = CGRect(x: 1168, y: -35, width: 254, height: 41)  // zone mesurée sur la machine
        let portee: CGFloat = 72
        #expect(opaciteFleches(curseur: CGPoint(x: 1295, y: -14), zone: zone, portee: portee) == 1)
        let approche = opaciteFleches(curseur: CGPoint(x: 1295, y: -71), zone: zone, portee: portee)
        #expect(approche > 0.4 && approche < 0.6)  // 36 pt sous la zone = mi-course
        #expect(opaciteFleches(curseur: CGPoint(x: 1295, y: -200), zone: zone, portee: portee) == 0)
        #expect(opaciteFleches(curseur: CGPoint(x: 1000, y: -14), zone: zone, portee: portee) == 0)
    }

    @Test("Portée nulle : les flèches n'existent que dans la bande, sans rampe")
    func porteeNulle() {
        // C'est le bas de course du curseur « Apparition » des Réglages, et une valeur qu'on
        // peut vouloir : plus rien ne s'allume en longeant le haut de l'écran.
        let zone = CGRect(x: 1168, y: -35, width: 254, height: 41)
        #expect(opaciteFleches(curseur: CGPoint(x: 1295, y: -14), zone: zone, portee: 0) == 1)
        #expect(opaciteFleches(curseur: CGPoint(x: 1295, y: -40), zone: zone, portee: 0) == 0)
        #expect(opaciteFleches(curseur: CGPoint(x: 1160, y: -14), zone: zone, portee: 0) == 0)
    }
}
