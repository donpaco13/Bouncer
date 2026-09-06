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
/// (290 pt de contenu, 451 pt de fenêtre minimale requise, seuil visibleFrame à 503 pt).
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
        // Le contenu de l'accueil nécessite 290 pt (34 pt marge haut + 290 pt contenu + 127 pt pied = 451 pt).
        // Le seuil de visibleFrame sans défilement (titre 28 + respiration 24 = 52 pt) vaut donc 503 pt.
        let seuilBienvenue = GeometrieAccueil.seuilVisibleFrameSansDefilement(pour: .bienvenue)
        #expect(seuilBienvenue == 503)

        let hauteurFenetreMin = GeometrieAccueil.hauteurMinimaleFenetreSansDefilement(pour: .bienvenue)
        #expect(hauteurFenetreMin == 451)

        // Dans la fenêtre standard de 580 pt, la marge restante est de 129 pt (580 - 451)
        // alors qu'elle était de 141 pt avec l'ancienne constante sous-estimée à 115 pt.
        let margeDisponible = GeometrieAccueil.hauteurVoulue - hauteurFenetreMin
        #expect(margeDisponible == 129)
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

/// Vérifie que la constante `hauteurPiedDePage` ne ment plus et correspond exactement
/// à la hauteur réelle mesurée par le moteur de rendu AppKit / SwiftUI.
///
/// Défaut D4 de la QA passe 4 : la constante valait 115 pt déclarée à la main.
/// La mesure réelle d'un `NSHostingView(rootView: PiedDePageAccueil)` à 660 pt de large
/// donne 127 pt (bouton principal 41 pt + espacement 18 pt + rangée navigation 14 pt +
/// espacement vers bouton ⌘W 18 pt + marges 36 pt = 127 pt).
@MainActor
struct PiedDePageTests {
    @Test func laHauteurReelleDuPiedDePageCorrespondALaConstante() {
        for etape in EtapeAccueil.allCases {
            let mesuree = PiedDePageAccueil.mesurerHauteur(pour: etape)
            #expect(
                mesuree == GeometrieAccueil.hauteurPiedDePage,
                "La hauteur mesurée du pied de page pour l'étape \(etape) (\(mesuree) pt) ne correspond pas à GeometrieAccueil.hauteurPiedDePage (\(GeometrieAccueil.hauteurPiedDePage) pt)"
            )
            #expect(mesuree == 127)
        }
    }

    @Test func laHauteurEstStrictementConstanteDUnEcranALAutre() {
        let hauteurs = EtapeAccueil.allCases.map { PiedDePageAccueil.mesurerHauteur(pour: $0) }
        let premiere = hauteurs[0]
        for hauteur in hauteurs {
            #expect(hauteur == premiere)
        }
    }
}
