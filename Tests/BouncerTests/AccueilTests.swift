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

/// Vérifie les seuils d'affichage et l'obligation de défilement (ScrollView) pour la fenêtre
/// d'accueil.
///
/// MESURÉ par la QA : sur un écran court (ou sous un certain seuil de `visibleFrame.height`),
/// le contenu dépasse la hauteur utile disponible. Sans `ScrollView`, le contenu est écrêté et
/// les boutons de navigation tombent hors d'atteinte.
///
/// Le mot « hello » ayant grandi (tracé vectoriel à 187 pt contre 132 pt pour le lettrage
/// manuscrit initial, soit +55 pt), la page `.bienvenue` est devenue la plus haute du parcours
/// (290 pt de contenu, 439 pt de fenêtre minimale requise, seuil visibleFrame à 491 pt).
struct DefilementAccueilTests {
    @Test func accueilDefilableQuandLeContenuDepasseLaHauteurUtile() throws {
        // 1. Vérifie la présence du ScrollView dans FenetreAccueil.swift
        let urlTests = URL(fileURLWithPath: #filePath)
        let repoRoot = urlTests
            .deletingLastPathComponent() // BouncerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // racine
        let fichierFenetre = repoRoot.appendingPathComponent("Sources/Bouncer/FenetreAccueil.swift")
        let sourceFenetre = try String(contentsOf: fichierFenetre, encoding: .utf8)

        let lignesCode = sourceFenetre
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("/*") && !$0.hasPrefix("*") }
        let aScrollView = lignesCode.contains { $0.contains("ScrollView {") || $0.hasPrefix("ScrollView") }
        #expect(aScrollView, "FenetreAccueil.swift doit obligatoirement intégrer un ScrollView")

        // 2. Vérifie que chaque étape dispose d'une hauteur utile suffisante au seuil de confort,
        // et que dès que l'écran passe sous ce seuil, le défilement est indispensable
        for etape in EtapeAccueil.allCases {
            let seuil = GeometrieAccueil.seuilVisibleFrameSansDefilement(pour: etape)
            let contenuRequis = GeometrieAccueil.hauteurMinimaleContenu(pour: etape)

            // Au seuil exact : le contenu tient pile dans la hauteur utile
            let hauteurAuSeuil = GeometrieAccueil.hauteurContenu(visibleFrameHeight: seuil)
            let utileAuSeuil = GeometrieAccueil.hauteurUtile(pourHauteurFenetre: hauteurAuSeuil)
            #expect(utileAuSeuil >= contenuRequis)

            // Juste en-dessous du seuil : la hauteur utile est inférieure au contenu requis
            let hauteurSousSeuil = GeometrieAccueil.hauteurContenu(visibleFrameHeight: seuil - 10)
            let utileSousSeuil = GeometrieAccueil.hauteurUtile(pourHauteurFenetre: hauteurSousSeuil)
            #expect(utileSousSeuil < contenuRequis)

            // Échoue formellement si le contenu dépasse la hauteur utile sans ScrollView
            let ecreteSansDefilement = (utileSousSeuil < contenuRequis) && !aScrollView
            #expect(!ecreteSansDefilement, "L'étape \(etape) est écrêtée sans ScrollView sur un écran de visibleFrame < \(seuil) pt")
        }
    }

    @Test func leSeuilRecalculeTientCompteDuNouveauTraceHello() {
        // Hello mesure 187 pt de haut au lieu de 132 pt (+55 pt).
        // Le contenu de l'accueil nécessite 290 pt (34 pt marge haut + 290 pt contenu + 115 pt pied = 439 pt).
        // Le seuil de visibleFrame sans défilement (titre 28 + respiration 24 = 52 pt) vaut donc 491 pt.
        let seuilBienvenue = GeometrieAccueil.seuilVisibleFrameSansDefilement(pour: .bienvenue)
        #expect(seuilBienvenue == 491)

        let hauteurFenetreMin = GeometrieAccueil.hauteurMinimaleFenetreSansDefilement(pour: .bienvenue)
        #expect(hauteurFenetreMin == 439)

        // Dans la fenêtre standard de 580 pt, la marge restante est de 141 pt (580 - 439)
        // alors qu'elle était de 196 pt (580 - 384) avec l'ancien hello de 132 pt.
        let margeDisponible = GeometrieAccueil.hauteurVoulue - hauteurFenetreMin
        #expect(margeDisponible == 141)
    }

    @Test func laFenetreNeDepassePasLEcranSurPetitsEcrans() {
        // Le plancher de 320 pt garantit que même pour un écran court de 450 pt,
        // la fenêtre (320 + 28 = 348 pt) reste entièrement contenue dans l'écran visible.
        let visibleCourt: CGFloat = 450
        let hauteur = GeometrieAccueil.hauteurContenu(visibleFrameHeight: visibleCourt)
        let cadreTotal = hauteur + GeometrieAccueil.hauteurBarreDeTitre
        #expect(cadreTotal <= visibleCourt)
        #expect(hauteur >= GeometrieAccueil.plancherHauteur)
    }
}
