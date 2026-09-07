//
// PistesFlechesTests.swift — les quatre pistes ouvertes le 2026-09-07 (« comment on peut rendre
// ça encore plus propre, les pistes sont ouvertes »).
//
// Ce que ces tests verrouillent AVANT tout : qu'aux valeurs par défaut, aucune des quatre ne
// change quoi que ce soit. Une piste qu'on propose ne doit rien coûter tant qu'on ne l'essaie
// pas — sans quoi ce n'est pas une proposition, c'est une décision prise à la place de François.
//
import Foundation
import Testing
@testable import BouncerCore

struct PistesFlechesTests {
    private let marge: CGFloat = 44
    private let taille: CGFloat = 22
    private let largeur: CGFloat = 254  // 166 + 2×44, la machine de référence

    // MARK: - P3, l'alignement dans la marge

    @Test("P3 — le défaut ne bouge pas d'un point")
    func alignementDefautIdentique() {
        let x = abscissesFleches(largeurOverlay: largeur, marge: marge, taille: taille)
        #expect(x.gauche == (marge - taille) / 2)
        #expect(x.droite == largeur - marge + (marge - taille) / 2)
    }

    @Test("P3 — 0 colle les deux chevrons au boîtier, 1 les pousse aux bords")
    func alignementSymetrique() {
        let colle = abscissesFleches(largeurOverlay: largeur, marge: marge, taille: taille, alignement: 0)
        // Boîtier : 44 → 210 dans le repère de l'overlay. Collé veut dire contre CES bords-là,
        // et de façon symétrique — c'est le point du calcul, un alignement lu à l'envers d'un côté.
        #expect(colle.gauche + taille == marge)
        #expect(colle.droite == largeur - marge)

        let bords = abscissesFleches(largeurOverlay: largeur, marge: marge, taille: taille, alignement: 1)
        #expect(bords.gauche == 0)
        #expect(bords.droite + taille == largeur)
    }

    @Test("P3 — un chevron ne sort jamais du panel, quel que soit l'alignement")
    func alignementResteDansLePanel() {
        for a in stride(from: CGFloat(-1), through: 2, by: 0.25) {
            let x = abscissesFleches(largeurOverlay: largeur, marge: marge, taille: taille, alignement: a)
            #expect(x.gauche >= 0)
            #expect(x.droite + taille <= largeur)
        }
    }

    // MARK: - P4, la courbe de révélation

    @Test("P4 — le défaut rend exactement l'ancienne courbe")
    func courbeDefautIdentique() {
        for p in stride(from: CGFloat(0), through: 1, by: 0.1) {
            let r = revelationFleches(progression: p, retrait: 8)
            #expect(abs(r.opacite - pow(p, 0.65)) < 0.0001)
        }
    }

    @Test("P4 — au-dessus de 1 le chevron se montre plus tard, en dessous plus tôt")
    func courbeChangeLeMoment() {
        let tot = revelationFleches(progression: 0.33, retrait: 8, courbe: 0.65).opacite
        let lineaire = revelationFleches(progression: 0.33, retrait: 8, courbe: 1).opacite
        let tard = revelationFleches(progression: 0.33, retrait: 8, courbe: 2.2).opacite
        #expect(tot > lineaire)
        #expect(lineaire > tard)
        // Le déploiement, lui, ne bouge pas : c'est ce que le test réel a validé.
        #expect(revelationFleches(progression: 0.33, retrait: 8, courbe: 2.2).decalage
                == revelationFleches(progression: 0.33, retrait: 8).decalage)
    }

    @Test("P4 — les deux bouts restent des bouts")
    func courbeBornes() {
        for c in [CGFloat(0.3), 0.65, 1, 3] {
            #expect(revelationFleches(progression: 0, retrait: 8, courbe: c).opacite == 0)
            #expect(revelationFleches(progression: 1, retrait: 8, courbe: c).opacite == 1)
        }
    }

    // MARK: - P1 et P2, les deux horloges

    @Test("P1/P2 — horloges au repos : le facteur vaut 1, toujours")
    func temporelNeutreAuDefaut() {
        for (entree, mouvement) in [(0.0, 0.0), (0.05, 3.0), (10.0, 60.0)] {
            #expect(facteurTemporel(depuisEntree: entree, depuisMouvement: mouvement,
                                    delai: 0, inactivite: 0) == 1)
        }
    }

    @Test("P2 — rien avant le délai, tout après, et un fondu entre les deux")
    func delaiAvantRevelation() {
        let delai = 0.4
        func f(_ t: TimeInterval) -> CGFloat {
            facteurTemporel(depuisEntree: t, depuisMouvement: 0, delai: delai, inactivite: 0)
        }
        #expect(f(0) == 0)
        #expect(f(0.39) == 0)
        #expect(f(delai + transitionTemporelle / 2) > 0)
        #expect(f(delai + transitionTemporelle / 2) < 1)
        #expect(f(delai + transitionTemporelle) == 1)
        #expect(f(10) == 1)
    }

    @Test("P1 — le chevron s'efface après l'immobilité, et en fondu")
    func effacementSurInactivite() {
        let seuil = 2.0
        func f(_ t: TimeInterval) -> CGFloat {
            facteurTemporel(depuisEntree: 99, depuisMouvement: t, delai: 0, inactivite: seuil)
        }
        #expect(f(0) == 1)
        #expect(f(1.99) == 1)
        #expect(f(seuil + transitionTemporelle / 2) < 1)
        #expect(f(seuil + transitionTemporelle / 2) > 0)
        #expect(f(seuil + transitionTemporelle) == 0)
        #expect(f(30) == 0)
    }

    @Test("P1+P2 — les deux horloges composent sans se contredire")
    func lesDeuxEnsemble() {
        // Arrivé depuis longtemps (délai franchi) mais immobile depuis longtemps : effacé.
        #expect(facteurTemporel(depuisEntree: 5, depuisMouvement: 5,
                                delai: 0.4, inactivite: 2) == 0)
        // Arrivé à l'instant : le délai domine, quel que soit l'état de l'autre horloge.
        #expect(facteurTemporel(depuisEntree: 0.1, depuisMouvement: 0,
                                delai: 0.4, inactivite: 2) == 0)
        // Présent depuis assez longtemps et la main bouge encore : plein.
        #expect(facteurTemporel(depuisEntree: 1, depuisMouvement: 0.05,
                                delai: 0.4, inactivite: 2) == 1)
    }

    // MARK: - Les quatre clés, relues depuis les préférences

    @Test("Les quatre réglages se posent depuis `defaults` et se bornent")
    func lesQuatreClesSeRelisent() {
        let suite = "bouncer.tests.pistes.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // Absentes : on retombe sur le comportement d'aujourd'hui (inactivité activée par défaut à 3.0 s).
        let vierge = Reglages(defaults: d)
        #expect(vierge.delaiRevelation == 0)
        #expect(vierge.inactiviteFleches == 3.0)
        #expect(vierge.alignementFleches == alignementFlechesDefaut)
        #expect(vierge.courbeRevelation == courbeRevelationDefaut)
        #expect(vierge.revelationTemporelleActive == true)

        // Écrites à la main (`defaults write`), y compris hors domaine : bornées, pas rejetées.
        d.set(0.35, forKey: "bouncer.delaiRevelation")
        d.set(99.0, forKey: "bouncer.inactiviteFleches")
        d.set(-4.0, forKey: "bouncer.alignementFleches")
        d.set(2.2, forKey: "bouncer.courbeRevelation")
        let regle = Reglages(defaults: d)
        #expect(regle.delaiRevelation == 0.35)
        #expect(regle.inactiviteFleches == 20)
        #expect(regle.alignementFleches == 0)
        #expect(regle.courbeRevelation == 2.2)
        #expect(regle.revelationTemporelleActive)

        regle.reinitialiser()
        #expect(regle.delaiRevelation == 0)
        #expect(regle.inactiviteFleches == 3.0)
        #expect(regle.alignementFleches == alignementFlechesDefaut)
        #expect(regle.courbeRevelation == courbeRevelationDefaut)
        #expect(regle.revelationTemporelleActive == true)
    }
}
