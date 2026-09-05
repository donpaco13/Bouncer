//
// AccueilTests.swift — les deux conditions qui rendent Bouncer inerte chez un inconnu, et qui ne
// se voient jamais sur la machine de son auteur (Accessibilité accordée depuis toujours, apps
// d'encoche installées depuis toujours).
//

import Foundation
import Testing
@testable import BouncerCore

struct AccueilTests {
    private let connues = ["a.b": "Bêta", "c.d": "Alpha"]

    @Test func sansAppDEncocheLAccueilNommeCellesQuIlConnait() {
        let etat = EtatAccueil(accessibiliteAccordee: true, appsEncocheInstallees: 0, connues: connues)
        // Triés : la fenêtre les énumère, l'ordre ne doit pas dépendre du hachage du dictionnaire.
        #expect(etat.appsAInstaller == ["Alpha", "Bêta"])
        // Autorisation accordée mais rien à arbitrer : l'app est inerte, l'accueil doit le dire.
        #expect(!etat.pretAServir)
    }

    @Test func avecAuMoinsUneAppInstalleeOnNeProposeRien() {
        let etat = EtatAccueil(accessibiliteAccordee: true, appsEncocheInstallees: 1, connues: connues)
        #expect(etat.appsAInstaller.isEmpty)
        #expect(etat.pretAServir)
    }

    @Test func sansAccessibiliteRienNEstPret() {
        let etat = EtatAccueil(accessibiliteAccordee: false, appsEncocheInstallees: 3, connues: connues)
        #expect(!etat.pretAServir)
    }

    @Test func leCatalogueDAmorcageEtLaTableDesNomsNePeuventPasDiverger() {
        #expect(amorcageCatalogue == Set(appsEncocheConnues.keys))
        #expect(!appsEncocheConnues.isEmpty)
    }
}

/// Le parcours en cinq écrans. Ses deux extrémités sont les seuls endroits où la navigation peut
/// casser, et ce sont ceux qu'on n'atteint jamais en développant.
struct ParcoursAccueilTests {
    @Test func lesCinqEtapesSEnchainentDansLOrdre() {
        #expect(EtapeAccueil.allCases.map(\.rawValue) == [0, 1, 2, 3, 4])
        #expect(EtapeAccueil.bienvenue.suivante == .probleme)
        #expect(EtapeAccueil.geste.suivante == .pret)
        #expect(EtapeAccueil.pret.precedente == .geste)
    }

    @Test func lesExtremitesNeDebordentPas() {
        // Au-delà du dernier écran il n'y a rien : c'est ce `nil` qui fait dire « Utiliser
        // Bouncer » au bouton plutôt que « Continuer », et qui referme la fenêtre.
        #expect(EtapeAccueil.pret.suivante == nil)
        #expect(EtapeAccueil.pret.estDerniere)
        #expect(EtapeAccueil.bienvenue.precedente == nil)
        #expect(!EtapeAccueil.bienvenue.estDerniere)
    }
}
