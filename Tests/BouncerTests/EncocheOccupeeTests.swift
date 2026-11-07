//
// EncocheOccupeeTests.swift — verrouille le défaut du 2026-09-07, dit dans ses mots : « quand on
// est sur le notch les flèches restent visibles alors que l'application du notch est ouverte,
// donc c'est pas propre propre ».
//
// Géométrie de la machine de référence : écran 1352×878, boîtier 593→759 (166×29). Les flèches
// vivent dans la rangée de la barre des menus, de part et d'autre du boîtier, et la fenêtre d'une
// app d'encoche (Vibe Island, 740×520) les recouvre.
//
// Le test le plus important n'est PAS celui de l'effacement : c'est `leSurvolDesFlechesNeLesEteintPas`.
// Les flèches sont dessinées dans les marges du boîtier ; s'éteindre quand le curseur y passe les
// rendrait invisibles au moment exact où on les survole.
//
import Foundation
import Testing
@testable import BouncerCore

struct EncocheOccupeeTests {
    private let boitier = CGRect(x: 593, y: 849, width: 166, height: 29)
    /// Vibe Island, relevé CGWindowList du 2026-09-05 ramené en repère AppKit.
    private let fenetre = CGRect(x: 306, y: 358, width: 740, height: 520)
    private var cadreFleches: CGRect { zoneSurvol(encoche: boitier, marge: 44) }

    private let surLeBoitier = CGPoint(x: 676, y: 860)
    private let surLeChevronGauche = CGPoint(x: 571, y: 863)
    private let surLeChevronDroit = CGPoint(x: 781, y: 863)
    private let surLIle = CGPoint(x: 676, y: 700)

    /// Rejoue un trajet de curseur et rend l'état après chaque point.
    private func trajet(_ points: [CGPoint], fenetre: CGRect?) -> [Bool] {
        var occupee = false
        return points.map {
            occupee = encocheOccupee(dejaOccupee: occupee, curseur: $0, boitier: boitier,
                                     fenetre: fenetre, cadreFleches: cadreFleches)
            return occupee
        }
    }

    @Test("Curseur sur le boîtier, app d'encoche présente : les flèches s'effacent")
    func effacementSurLeBoitier() {
        #expect(trajet([surLeBoitier], fenetre: fenetre) == [true])
    }

    @Test("Survoler les flèches sans toucher le boîtier ne les éteint pas")
    func leSurvolDesFlechesNeLesEteintPas() {
        #expect(trajet([surLIle, surLeChevronGauche, surLeChevronDroit], fenetre: fenetre)
                == [false, false, false])
    }

    @Test("App déployée : les flèches restent effacées tant que le curseur reste sur sa fenêtre")
    func resteEffaceeSurLaFenetre() {
        #expect(trajet([surLeBoitier, surLIle, surLeChevronGauche], fenetre: fenetre)
                == [true, true, true])
    }

    @Test("Sortir de la fenêtre libère, et y revenir sans toucher le boîtier ne réoccupe pas")
    func sortieLibere() {
        let dehors = CGPoint(x: 100, y: 100)
        #expect(trajet([surLeBoitier, dehors, surLIle, surLeChevronDroit], fenetre: fenetre)
                == [true, false, false, false])
    }

    @Test("Aucune app d'encoche à l'écran : rien à effacer")
    func aucuneApp() {
        #expect(trajet([surLeBoitier, surLIle], fenetre: nil) == [false, false])
        #expect(trajet([surLeBoitier], fenetre: .zero) == [false])
    }

    @Test("Une fenêtre qui n'atteint pas les flèches ne les efface pas")
    func fenetreTropEtroite() {
        // Une île qui reste dans le boîtier : rien n'est dessiné sous les flèches.
        // Elle touche la bande par le boîtier — toute fenêtre d'encoche le fait — mais pas les marges.
        for etroite in [CGRect(x: 620, y: 849, width: 110, height: 29), boitier] {
            #expect(trajet([surLeBoitier], fenetre: etroite) == [false], "fenêtre \(etroite)")
        }
        // Un seul point de débord dans une marge suffit à compter.
        let debordante = CGRect(x: 592, y: 849, width: 168, height: 29)
        #expect(trajet([surLeBoitier], fenetre: debordante) == [true])
    }
}
