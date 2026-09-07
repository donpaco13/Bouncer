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

    /// Portée d'approche par défaut : la même que celle qui commande l'opacité des chevrons.
    private let portee: CGFloat = 72
    /// Les deux cibles de clic, en repère écran : 22 pt centrés dans chaque marge de 44.
    /// Gauche x 560→582, droite x 770→792, toutes deux en y 817,5→839,5.
    private var cibles: [CGRect] {
        let c = cadresFleches(overlay: cadreFleches.size, marge: marge)
        return [c.gauche, c.droite].map { $0.offsetBy(dx: cadreFleches.minX, dy: cadreFleches.minY) }
    }

    private func occupee(curseur: CGPoint, fenetre: CGRect?) -> Bool {
        encocheOccupee(curseur: curseur, bandeEncoche: bande, cadreFleches: cadreFleches,
                       fenetre: fenetre, ciblesFleches: cibles, portee: portee)
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
        // Le chevron gauche est en x 560→582, y 817,5→839,5. Un curseur qui l'approche par le
        // bas, par le côté, ou qui est posé DESSUS, est dans la fenêtre de l'app déployée — et ce
        // n'est pas une raison de l'effacer. C'est l'ABORD de la cible qui est protégé, pas ses
        // 22 pt : une flèche qui n'apparaît qu'une fois le curseur dessus est invisible.
        for curseur in [
            CGPoint(x: 571, y: 828),  // sur le chevron
            CGPoint(x: 571, y: 800),  // juste dessous
            CGPoint(x: 500, y: 828),  // par la gauche, à 60 pt de la cible
            CGPoint(x: 781, y: 828),  // sur le chevron droit
            CGPoint(x: 830, y: 828),  // par la droite, à 38 pt de la cible droite
        ] {
            #expect(!occupee(curseur: curseur, fenetre: fenetreDeployee), "curseur \(curseur)")
        }
    }

    @Test("Curseur posé sur le widget déployé, loin des chevrons : ils s'effacent")
    func effacementSurLeWidget() {
        // Le défaut du 2026-09-07 : app déployée en widget média large, les deux chevrons
        // toujours dessinés à ses extrémités. `bandeEncoche.contains` ne pouvait rien y faire —
        // le curseur est sur le WIDGET, une rangée ou plus SOUS la rangée de l'encoche.
        for curseur in [
            CGPoint(x: 676, y: 790),  // sous l'encoche, en pleine île déployée
            CGPoint(x: 676, y: 828),  // au milieu de la bande, à 94 pt des deux cibles
            CGPoint(x: 400, y: 600),  // au fond du widget
            CGPoint(x: 1000, y: 700), // dans le coin opposé
        ] {
            #expect(occupee(curseur: curseur, fenetre: fenetreDeployee), "curseur \(curseur)")
        }
    }

    @Test("Sous la bande, en plein widget : les chevrons s'effacent même sous une cible")
    func effacementSousLaBande() {
        // Le retour du 2026-09-07, deuxième passe : « dès que je suis un peu plus bas sur le
        // panel de l'app qui s'est ouverte, en dessous de la zone de l'encoche, ils
        // réapparaissent ». La protection était un DISQUE de 72 pt autour de la cible : elle
        // descendait aussi bas qu'elle s'étendait sur les côtés, et couvrait la rangée entière
        // sous l'encoche. Mesuré avant correctif, curseur 40 pt sous la bande : opacité de cible
        // 0,396 en x 571 et 0,346 en x 600 — protégé, donc chevrons allumés.
        //
        // La colonne x 571 est celle du chevron gauche : c'est le pire cas, celui qui reste
        // protégé le plus longtemps.
        for dessous in [40.0, 60.0, 80.0, 150.0] as [CGFloat] {
            for x in [571.0, 600.0, 676.0, 781.0] as [CGFloat] {
                let curseur = CGPoint(x: x, y: cadreFleches.minY - dessous)
                #expect(fenetreDeployee.contains(curseur), "hors fenêtre \(curseur)")
                #expect(occupee(curseur: curseur, fenetre: fenetreDeployee), "curseur \(curseur)")
            }
        }
    }

    @Test("La protection s'arrête à une hauteur de chevron sous la cible")
    func frontiereBasseDeLaProtection() {
        // Contre-épreuve de la frontière, des deux côtés et à 0,5 pt près : au-dessus elle tient
        // (c'est le trajet vers le bouton), en dessous elle lâche (c'est le widget).
        let cible = cibles[0]
        let plancher = cible.minY - cible.height  // 795,5
        #expect(!occupee(curseur: CGPoint(x: cible.midX, y: plancher + 0.5),
                         fenetre: fenetreDeployee))
        #expect(occupee(curseur: CGPoint(x: cible.midX, y: plancher - 0.5),
                        fenetre: fenetreDeployee))
        // Latéralement, en revanche, la portée entière reste protégée : c'est par là que la main
        // arrive quand une app est déployée, la rangée de l'encoche effaçant déjà par le haut.
        #expect(!occupee(curseur: CGPoint(x: cible.minX - portee + 0.5, y: cible.midY),
                         fenetre: fenetreDeployee))
        #expect(occupee(curseur: CGPoint(x: cible.minX - portee - 0.5, y: cible.midY),
                        fenetre: fenetreDeployee))
    }

    @Test("Les deux règles se composent sans trou : la marge entre cible et bord de bande")
    func aucunTrouEntreLesDeuxRegles() {
        // Le piège que la version « 22 pt nus » aurait introduit : la cible ne fait que 22 pt de
        // haut dans une bande de 29, et il reste 3,5 pt en haut comme en bas. Une main qui y
        // passe est à 3 pt du bouton — l'éteindre là, c'est l'éteindre sous ses doigts.
        let gauche = cibles[0]
        #expect(gauche == CGRect(x: 560, y: 817.5, width: 22, height: 22))
        #expect(cadreFleches.minY < gauche.minY && gauche.maxY < cadreFleches.maxY)
        for y in [cadreFleches.minY + 0.5, gauche.minY - 0.5, gauche.maxY + 0.5, cadreFleches.maxY - 0.5] {
            #expect(!occupee(curseur: CGPoint(x: gauche.midX, y: y), fenetre: fenetreDeployee),
                    "y \(y)")
        }
        // Et aucun trou non plus entre le haut de la bande et le bas de la rangée de l'encoche :
        // au-dessus de `cadreFleches.maxY`, c'est `bandeEncoche` qui prend le relais, et elle
        // efface. Les deux verdicts sont opposés mais la frontière est franche, pas trouée.
        #expect(bande.minY == cadreFleches.maxY)
    }

    @Test("Portée nulle : la protection retombe sur les 22 pt de la cible")
    func porteeNulle() {
        // Réglage extrême, cohérent avec lui-même : à portée 0 les flèches sont déjà binaires.
        func occupeeSansPortee(_ curseur: CGPoint) -> Bool {
            encocheOccupee(curseur: curseur, bandeEncoche: bande, cadreFleches: cadreFleches,
                           fenetre: fenetreDeployee, ciblesFleches: cibles, portee: 0)
        }
        #expect(!occupeeSansPortee(CGPoint(x: 571, y: 828)))  // sur la cible
        #expect(occupeeSansPortee(CGPoint(x: 500, y: 828)))   // hors de la cible
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
