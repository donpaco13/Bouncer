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

    // MARK: - Durée de vie du détecteur (bug QA #8, 2026-09-05)
    //
    // Le détecteur ne voit jamais qu'on l'a remplacé : ces tests-là ne portent donc pas sur sa
    // décision (verrouillée au-dessus) mais sur QUAND `NotchOverlay` le remplace.

    /// Rejoue la boucle réelle de `NotchOverlay` : le monitor de défilement s'attache quand
    /// `doitEcouter` le veut, se détache sinon, et chaque attache repart d'une session neuve.
    /// `sortiesDeZone` liste les index d'événements pendant lesquels le curseur a débordé.
    private func basculesAvecOscillation(
        sortiesDeZone: Set<Int>,
        politique: (SessionSwipe, Bool) -> Bool
    ) -> Int {
        var session = SessionSwipe()
        var attache = false
        var total = 0

        for (i, e) in gesteEnregistre().enumerated() {
            let dansLaZone = !sortiesDeZone.contains(i)
            // Le monitor `.mouseMoved` réévalue l'attache à chaque mouvement du curseur.
            let voulu = politique(session, dansLaZone)
            if voulu, !attache {
                session.demarre()
                attache = true
            } else if !voulu {
                attache = false
                continue
            }
            let evenement = EvenementDefilement(
                phase: e.phase, inertie: e.inertie, deltaX: e.deltaX, deltaY: e.deltaY,
                instant: e.instant, dansLaZone: dansLaZone
            )
            if session.recoit(evenement) == .bascule { total += 1 }
        }
        return total
    }

    /// L'ancienne règle : le monitor suit le curseur, point. C'est elle qui doublait.
    private func ancienneRegle(_ session: SessionSwipe, _ dansLaZone: Bool) -> Bool {
        dansLaZone
    }

    private func regleActuelle(_ session: SessionSwipe, _ dansLaZone: Bool) -> Bool {
        session.doitEcouter(swipeActif: true, curseurDansLaZone: dansLaZone)
    }

    @Test("Un geste qui effleure la bordure de la zone ne produit toujours qu'UNE bascule")
    func oscillationEnBordDeZone() {
        // Index 7 : après la bascule (le seuil tombe au 4e événement) et avant la fin du geste —
        // c'est-à-dire pile là où un détecteur réarmé a de quoi produire un second déclenchement.
        #expect(basculesAvecOscillation(sortiesDeZone: [7], politique: regleActuelle) == 1)
    }

    @Test("Le témoin du bug : la règle « le monitor suit le curseur » en produisait DEUX")
    func ancienneRegleDoublait() {
        // Ce test n'exige rien du code de production ; il atteste que le scénario ci-dessus est
        // bien celui qui cassait, sans quoi le test précédent passerait pour de mauvaises raisons.
        #expect(basculesAvecOscillation(sortiesDeZone: [7], politique: ancienneRegle) == 2)
    }

    @Test("Hors geste, le monitor se détache dès que le curseur sort")
    func detacheHorsGeste() {
        let session = SessionSwipe()
        #expect(session.doitEcouter(swipeActif: true, curseurDansLaZone: false) == false)
        #expect(session.doitEcouter(swipeActif: true, curseurDansLaZone: true))
        // Le mode « flèches seules » reste prioritaire : rien à écouter, geste en cours ou non.
        #expect(session.doitEcouter(swipeActif: false, curseurDansLaZone: true) == false)
    }

    @Test("La fin du geste relâche la rétention du monitor")
    func finDeGesteRelache() {
        var session = SessionSwipe()
        session.demarre()
        _ = session.recoit(EvenementDefilement(phase: .debut, inertie: false, deltaX: 0, deltaY: 0,
                                               instant: 0, dansLaZone: true))
        #expect(session.doitEcouter(swipeActif: true, curseurDansLaZone: false))
        _ = session.recoit(EvenementDefilement(phase: .fin, inertie: false, deltaX: 0, deltaY: 0,
                                               instant: 0.5, dansLaZone: false))
        #expect(session.doitEcouter(swipeActif: true, curseurDansLaZone: false) == false)
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

/// La révélation des flèches — ce que `opaciteFleches` ne disait pas.
///
/// La rampe linéaire existait déjà et ne suffisait pas : SEULE L'OPACITÉ variait, donc la flèche
/// apparaissait sans se déployer. Ce que ces tests verrouillent, c'est la propriété demandée —
/// « si on se rapproche un peu elle sort un tout petit peu, sinon elle se déploie complètement ».
struct RevelationTests {
    @Test func lesTroisGrandeursSontNullesEtPleinesAuxDeuxBouts() {
        let loin = revelationFleches(progression: 0, retrait: 8)
        #expect(loin.opacite == 0)
        #expect(loin.decalage == -8)   // entièrement rentrée
        #expect(loin.echelle == 0.82)

        let pres = revelationFleches(progression: 1, retrait: 8)
        #expect(pres.opacite == 1)
        #expect(pres.decalage == 0)    // à sa place
        #expect(pres.echelle == 1)
    }

    @Test func laProgressionEstBorneeAuxDeuxBouts() {
        #expect(revelationFleches(progression: -3, retrait: 8) == revelationFleches(progression: 0, retrait: 8))
        #expect(revelationFleches(progression: 12, retrait: 8) == revelationFleches(progression: 1, retrait: 8))
    }

    @Test func laFlecheSortEtSeVoitDejaAMiChemin() {
        let mi = revelationFleches(progression: 0.5, retrait: 8)
        // L'opacité monte plus vite que la progression : à mi-portée la flèche est franchement là.
        #expect(mi.opacite > 0.5)
        // Le déploiement, lui, est amorti : à mi-chemin la flèche est à mi-course exactement.
        #expect(abs(mi.decalage - (-4)) < 0.001)
    }

    @Test func deLoinLaFlecheEstUnSoupconEtNonRien() {
        // « si on se rapproche un peu elle sort un tout petit peu » : au tiers de la portée,
        // visible mais encore largement rentrée.
        let tiers = revelationFleches(progression: 1.0 / 3, retrait: 8)
        #expect(tiers.opacite > 0.4)
        #expect(tiers.decalage < -4)
    }

    @Test func aRetraitNulSeuleLOpaciteVarie() {
        // L'ancien comportement reste atteignable : c'est ce que promet le curseur à zéro.
        for p in stride(from: CGFloat(0), through: 1, by: 0.25) {
            #expect(revelationFleches(progression: p, retrait: 0).decalage == 0)
        }
    }
}

/// Le garde qui a écarté l'événement — la moitié utile du journal.
///
/// Sans elle, un swipe raté ne laisse aucune trace : on ne voit que les événements acceptés, donc
/// rien de ce qu'on cherche. C'est ce point aveugle qui a laissé passer la vraie cause (une zone
/// écoutée de 254 pt sous une île visible de 740) pendant que deux correctifs au jugé échouaient.
struct RaisonTests {
    private func evt(_ phase: EvenementDefilement.Phase, dx: CGFloat = 20, dy: CGFloat = 0,
                     inertie: Bool = false, zone: Bool = true, t: TimeInterval = 0) -> EvenementDefilement {
        EvenementDefilement(phase: phase, inertie: inertie, deltaX: dx, deltaY: dy, instant: t, dansLaZone: zone)
    }

    @Test func chaqueRejetNommeSonGarde() {
        var d = DetecteurSwipe()

        _ = d.recoit(evt(.encours, inertie: true))
        #expect(d.raison == .inertie)

        _ = d.recoit(evt(.debut))
        #expect(d.raison == .debutDeGeste)

        // Le cas qui expliquait les swipes ratés : le geste est bon, il est juste posé ailleurs.
        _ = d.recoit(evt(.encours, zone: false))
        #expect(d.raison == .horsZone)

        _ = d.recoit(evt(.encours, dx: 2))
        #expect(d.raison == .sousLeSeuil)

        // Deux gardes distincts et non un seul : « trop court » et « c'était un défilement
        // vertical » demandent deux correctifs opposés, et les confondre les rend illisibles.
        _ = d.recoit(evt(.encours, dx: 4, dy: 40))
        #expect(d.raison == .dominanceVerticale)

        _ = d.recoit(evt(.fin))
        #expect(d.raison == .finDeGeste)
    }

    @Test func apresLaBasculeLeResteDuGesteEstNomme() {
        var d = DetecteurSwipe()
        _ = d.recoit(evt(.debut))
        #expect(d.recoit(evt(.encours)) == .bascule)
        #expect(d.raison == .bascule)
        // Une seule détente par geste : le reste du mouvement n'est pas « trop court », il est
        // désarmé — et le journal doit le dire, sinon on cherche un seuil qui n'y est pour rien.
        _ = d.recoit(evt(.encours))
        #expect(d.raison == .nonArme)
    }

    @Test("L'instrumentation du geste lit bouncer.traceSwipe et documente le bon bundleID (N7)")
    func traceSwipeActivationEtBundleID() {
        let suite = UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        #expect(!TraceSwipe.estActif(defaults: d, env: [:]))

        d.set(true, forKey: TraceSwipe.clePreference)
        #expect(TraceSwipe.estActif(defaults: d, env: [:]))

        #expect(TraceSwipe.bundleIDReel == "io.github.donpaco13.bouncer")
        #expect(TraceSwipe.clePreference == "bouncer.traceSwipe")
    }
}
