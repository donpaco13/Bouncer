//
// EncocheOccupeeTests.swift — verrouille le correctif du 2026-09-07, dit dans ses mots : « quand
// on est sur le notch les flèches restent visibles alors que l'application du notch est ouverte,
// donc c'est pas propre propre ».
//
// La géométrie est celle de la machine de référence, la même que `ZoneSurvolTests` : écran
// 1352×878, boîtier 593→759 (166×29), rangée de barre des menus 35 pt. Les chevrons vivent donc
// une rangée plus bas, en y 814→843, et la fenêtre d'une app d'encoche déployée (Vibe Island,
// 740×520) les recouvre entièrement.
//
// Le test le plus important n'est PAS celui qui vérifie l'effacement : c'est
// `flechesIntactesQuandOnDescendVersElles`. Le piège de ce correctif était de s'effacer sur la
// présence du curseur dans la FENÊTRE de l'app — ce qui aurait éteint les chevrons au moment
// exact où l'on va les cliquer, et cassé le bouton que François valide.
//
import Foundation
import Testing
@testable import BouncerCore

struct EncocheOccupeeTests {
    private let boitier = CGRect(x: 593, y: 849, width: 166, height: 29)
    private let marge: CGFloat = 44
    private let rangee: CGFloat = 35
    /// Vibe Island déployée, relevé CGWindowList du 2026-09-05 ramené en repère AppKit.
    private let fenetreDeployee = CGRect(x: 306, y: 358, width: 740, height: 520)

    private var survol: CGRect { zoneSurvol(encoche: boitier, marge: marge) }
    private var bande: CGRect { bandeEncoche(survol: survol, hauteurRangee: rangee) }
    private var cadreFleches: CGRect { bandeFleches(survol: survol, hauteurRangee: rangee) }

    private func occupee(curseur: CGPoint, fenetre: CGRect?) -> Bool {
        encocheOccupee(curseur: curseur, bandeEncoche: bande, cadreFleches: cadreFleches,
                       fenetre: fenetre)
    }

    @Test("La bande de l'encoche couvre TOUTE la rangée, pas seulement le boîtier")
    func bandeCouvreLaRangeeEntiere() {
        // Le boîtier fait 29 pt, la rangée 35 : les 6 pt d'écart tombaient entre les deux bandes.
        #expect(bande.height == rangee)
        #expect(bande.maxY == survol.maxY)
        // Aucun trou entre le bas de la rangée et le haut de la bande des flèches.
        #expect(bande.minY == cadreFleches.maxY)
    }

    @Test("Curseur sur l'encoche, app déployée : les flèches s'effacent")
    func effacementSurLEncoche() {
        #expect(occupee(curseur: CGPoint(x: 676, y: 860), fenetre: fenetreDeployee))
        // Y compris dans les marges latérales, où l'île déployée déborde du boîtier.
        #expect(occupee(curseur: CGPoint(x: 560, y: 860), fenetre: fenetreDeployee))
        #expect(occupee(curseur: CGPoint(x: 795, y: 860), fenetre: fenetreDeployee))
        // Y compris dans les 6 pt que le boîtier ne couvrait pas.
        #expect(occupee(curseur: CGPoint(x: 676, y: 845), fenetre: fenetreDeployee))
    }

    @Test("Le chemin vers le chevron ne l'éteint jamais")
    func flechesIntactesQuandOnDescendVersElles() {
        // Le chevron gauche est en x 560→582, y 814→843. Un curseur qui l'approche par le bas,
        // par le côté, ou qui est posé DESSUS, est dans la fenêtre de l'app déployée — et ce
        // n'est pas une raison de l'effacer.
        for curseur in [
            CGPoint(x: 571, y: 828),  // sur le chevron
            CGPoint(x: 571, y: 800),  // juste dessous
            CGPoint(x: 500, y: 828),  // par la gauche
            CGPoint(x: 676, y: 790),  // sous l'encoche, en pleine île déployée
            CGPoint(x: 781, y: 828),  // sur le chevron droit
        ] {
            #expect(!occupee(curseur: curseur, fenetre: fenetreDeployee), "curseur \(curseur)")
        }
    }

    @Test("Aucune app d'encoche à l'écran : rien à effacer")
    func aucuneApp() {
        #expect(!occupee(curseur: CGPoint(x: 676, y: 860), fenetre: nil))
        #expect(!occupee(curseur: CGPoint(x: 676, y: 860), fenetre: .zero))
    }

    @Test("Une fenêtre qui n'atteint pas les chevrons ne les efface pas")
    func fenetreTropEtroite() {
        // Une île qui reste dans le boîtier : rien n'est dessiné sous les chevrons, donc il n'y a
        // rien de sale à corriger. C'est la même règle que la pastille de contraste.
        let etroite = CGRect(x: 620, y: 849, width: 110, height: 29)
        #expect(!etroite.intersects(cadreFleches))
        #expect(!occupee(curseur: CGPoint(x: 676, y: 860), fenetre: etroite))
    }
}
