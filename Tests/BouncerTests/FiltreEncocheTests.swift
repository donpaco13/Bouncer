//
// FiltreEncocheTests.swift — le filtre qui décide « ceci est une app d'encoche », verrouillé sur
// des mesures et non sur des cas inventés.
//
// Tous les nombres ci-dessous sont des relevés `CGWindowListCopyWindowInfo` faits sur le MacBook de
// référence (écran interne 1352×878 posé à droite d'un écran externe 2560×1440, `screens[0]` étant
// l'externe). Boîtier caméra relevé de 1212 à 1378 en x, sur 29 pt de haut. Les intrus qu'on avait pu
// reproduire au premier relevé : Discord et une fenêtre Finder poussées le plus haut possible sur
// l'écran interne s'arrêtent à 35 pt du bord, plafonnées par la barre de menus.
//
// Handy et l'alerte centrée viennent du relevé du 5 septembre 2026, celui qui a expliqué pourquoi
// `com.pais.handy` et `com.apple.UserNotificationCenter` étaient entrés au catalogue : une fenêtre
// posée sur l'écran EXTERNE satisfaisait gratuitement une première condition qui n'était bornée
// que par le bas. Ils gardent la borne haute.

import CoreGraphics
import Testing

@testable import BouncerCore

/// Repère `CGWindowList` (origine en haut à gauche de `screens[0]`), tel que l'API le rend.
private func bounds(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> [String: CGFloat] {
    ["X": x, "Y": y, "Width": w, "Height": h]
}

@Suite("Filtre d'encoche — départager une app d'encoche d'une fenêtre qui l'effleure")
struct FiltreEncocheTests {
    private let hauteurEcranPrincipal: CGFloat = 1440
    private let cadreEcran = CGRect(x: 619, y: -878, width: 1352, height: 878)
    private let zone = CGRect(x: 1212, y: -29, width: 166, height: 29)

    private func accepte(_ b: [String: CGFloat]) -> Bool {
        estFenetreEncoche(zone, cadreEcran: cadreEcran, bounds: b, hauteurEcranPrincipal: hauteurEcranPrincipal)
    }

    @Test("Vibe Island passe : 740 pt collés au bord haut, boîtier recouvert de 925 à 1665")
    func vibeIsland() {
        #expect(accepte(bounds(x: 925, y: 1440, w: 740, h: 520)))
    }

    @Test("boringNotch passe : 640 pt collés au bord haut, boîtier recouvert de 975 à 1615")
    func boringNotch() {
        #expect(accepte(bounds(x: 975, y: 1440, w: 640, h: 210)))
    }

    @Test("Un overlay plein écran est recalé — il est collé au bord haut et recouvre le boîtier")
    func overlayPleinEcran() {
        // Le Dock (1352×878) et l'overlay de capture d'écran ont exactement ce profil : ils
        // passeraient les deux premières conditions. Seule la largeur les sépare des vraies.
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 878)) == false)
    }

    @Test("La barre de menus est recalée pour la même raison : toute la largeur de l'écran")
    func barreDeMenus() {
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 34)) == false)
    }

    @Test("La plus large icône de barre de menus relevée (146 pt) ne contient pas un boîtier de 166")
    func iconeDeBarreDeMenus() {
        // Posée volontairement à cheval sur le boîtier, ce que macOS ne fait jamais : même là,
        // elle ne le recouvre pas en entier. C'est ce que verrouille la deuxième condition.
        #expect(accepte(bounds(x: 1250, y: 1440, w: 146, h: 34)) == false)
    }

    @Test("Discord poussé le plus haut possible reste 35 pt sous le bord : recalé")
    func discordEnHautDeLEcran() {
        #expect(accepte(bounds(x: 900, y: 1475, w: 700, h: 500)) == false)
    }

    @Test("Une fenêtre Finder poussée le plus haut possible : recalée pour la même raison")
    func finderEnHautDeLEcran() {
        #expect(accepte(bounds(x: 900, y: 1475, w: 800, h: 360)) == false)
    }

    @Test("La pastille de Handy, en haut de l'écran EXTERNE, est recalée")
    func handySurLEcranExterne() {
        // Le faux positif qui a mis `com.pais.handy` au catalogue, relevé tel quel le 5 septembre
        // 2026 : `X:1152→1408, Y CGWindow 1379, 256×46`, soit un sommet AppKit à +61 pt — 61 pt
        // au-dessus du bord haut de l'écran à encoche, qui est à 0. Elle recouvre les abscisses du
        // boîtier par pure coïncidence entre deux écrans, et tient sous le plafond de largeur :
        // seule la borne HAUTE de la première condition la recale.
        #expect(accepte(bounds(x: 1152, y: 1379, w: 256, h: 46)) == false)
    }

    @Test("Une alerte centrée sur l'écran externe est recalée pour la même raison")
    func alerteCentreeSurLEcranExterne() {
        // Le profil de `com.apple.UserNotificationCenter`, l'autre intrus du catalogue : 420 pt
        // centrés sur l'écran externe (1070→1490) contiennent le boîtier 1212→1378, et son sommet
        // est très au-dessus de celui de l'écran interne.
        #expect(accepte(bounds(x: 1070, y: 1240, w: 420, h: 200)) == false)
    }

    @Test("Une fenêtre décalée qui n'effleure le boîtier que par un bord est recalée")
    func fenetreQuiEffleure() {
        // 600 pt collés au bord haut, posés de 700 à 1300 : elle mord sur le boîtier (1212→1378)
        // sans le contenir. C'était exactement ce que l'ancien `intersects` laissait passer.
        #expect(accepte(bounds(x: 700, y: 1440, w: 600, h: 300)) == false)
    }

    // MARK: Les trois apps de 1352 pt — la découverte les refuse, et c'est voulu

    // Campagne du 5 septembre 2026, `docs/COMPATIBILITE.md` §3.2 : NotchNook, Notchy et Mew Notch
    // dessinent leur encoche dans un calque qui couvre TOUTE la largeur de l'écran porteur — 1352 pt
    // sur 1352. La seule mesure relevée sur elles est cette largeur, et c'est la seule dont le filtre
    // ait besoin : ni la condition 1 ni la 2 ne lisent la hauteur (elle s'annule dans la conversion
    // de repère), et la 3 ne lit que la largeur. Les hauteurs ci-dessous sont donc arbitraires et
    // ne portent aucun verdict.
    //
    // Les laisser entrer par la découverte demanderait de relever le plafond à 100 %, ce qui
    // réadmettrait AU CATALOGUE le Dock, la barre du Window Server et les overlays de capture, qui
    // ont exactement le même profil. Le catalogue de la machine de référence a déjà contenu cinq
    // intrus sur sept pour cette raison. Elles restent donc dehors ici, et entrent par leur
    // bundleID (`appsEncocheConnues`) — cf. la seconde suite.

    @Test("NotchNook, 1352 pt sur un écran de 1352 : refusée par la découverte")
    func notchNookHorsDeLaDecouverte() {
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 878)) == false)
    }

    @Test("Notchy, même profil, même refus")
    func notchyHorsDeLaDecouverte() {
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 200)) == false)
    }

    @Test("Mew Notch, même profil, même refus")
    func mewNotchHorsDeLaDecouverte() {
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 120)) == false)
    }

    @Test("Arc en plein écran, collée au bord haut : refusée elle aussi")
    func arcEnPleinEcran() {
        // Le scan l'écarte plus tôt (`layer > 0` : une fenêtre plein écran reste au layer 0), mais
        // le filtre ne s'appuie pas là-dessus — Arc figurait au catalogue v1 et n'y revient pas,
        // même si un jour elle passait au layer flottant.
        #expect(accepte(bounds(x: 619, y: 1440, w: 1352, h: 878)) == false)
    }
}

/// La seconde question, celle qui gagne les trois apps : « l'app que je tiens DÉJÀ par son
/// bundleID couvre-t-elle l'encoche ? »
///
/// `couvreEncoche` ne sert qu'à `fenetreVisibleDansNotch(pid:)`, donc à un pid que l'appelant est
/// allé chercher dans son catalogue. Rien n'est appris par ce chemin — `catalogue.apprendre` ne se
/// lit que dans le scan de découverte — donc aucun faux positif ne peut en sortir. Ce que ces tests
/// verrouillent, c'est que le plafond de largeur est la SEULE chose qui tombe : les huit intrus de
/// la suite ci-dessus restent dehors des deux côtés, parce qu'ils échouent aux conditions 1 ou 2.
@Suite("Présence par pid — mesurer une app déjà nommée, sans le plafond de largeur")
struct CouvertureEncocheTests {
    private let hauteurEcranPrincipal: CGFloat = 1440
    private let cadreEcran = CGRect(x: 619, y: -878, width: 1352, height: 878)
    private let zone = CGRect(x: 1212, y: -29, width: 166, height: 29)

    private func couvre(_ b: [String: CGFloat]) -> Bool {
        couvreEncoche(zone, cadreEcran: cadreEcran, bounds: b, hauteurEcranPrincipal: hauteurEcranPrincipal)
    }

    @Test("NotchNook est enfin mesurable : son calque de 1352 pt couvre le boîtier au bord haut")
    func notchNook() {
        #expect(couvre(bounds(x: 619, y: 1440, w: 1352, h: 878)))
    }

    @Test("Notchy aussi")
    func notchy() {
        #expect(couvre(bounds(x: 619, y: 1440, w: 1352, h: 200)))
    }

    @Test("Mew Notch aussi")
    func mewNotch() {
        #expect(couvre(bounds(x: 619, y: 1440, w: 1352, h: 120)))
    }

    @Test("Les quatre apps déjà régies restent mesurées comme avant")
    func lesRegiesNeBougentPas() {
        #expect(couvre(bounds(x: 925, y: 1440, w: 740, h: 520)))  // Vibe Island, 740 pt
        #expect(couvre(bounds(x: 975, y: 1440, w: 640, h: 210)))  // boringNotch, 640 pt
    }

    @Test("La pastille de Handy, sur l'écran EXTERNE, reste dehors : c'est la condition 1 qui tient")
    func handySurLEcranExterne() {
        #expect(couvre(bounds(x: 1152, y: 1379, w: 256, h: 46)) == false)
    }

    @Test("L'alerte centrée sur l'écran externe reste dehors, même raison")
    func alerteCentreeSurLEcranExterne() {
        #expect(couvre(bounds(x: 1070, y: 1240, w: 420, h: 200)) == false)
    }

    @Test("La plus large icône de statut relevée (146 pt) reste dehors : c'est la condition 2")
    func iconeDeBarreDeMenus() {
        #expect(couvre(bounds(x: 1250, y: 1440, w: 146, h: 34)) == false)
    }

    @Test("Discord poussée le plus haut possible reste 35 pt sous le bord : dehors")
    func discordEnHautDeLEcran() {
        #expect(couvre(bounds(x: 900, y: 1475, w: 700, h: 500)) == false)
    }

    @Test("Une fenêtre Finder poussée le plus haut possible : dehors, même raison")
    func finderEnHautDeLEcran() {
        #expect(couvre(bounds(x: 900, y: 1475, w: 800, h: 360)) == false)
    }

    @Test("Une fenêtre qui n'effleure le boîtier que par un bord : dehors")
    func fenetreQuiEffleure() {
        #expect(couvre(bounds(x: 700, y: 1440, w: 600, h: 300)) == false)
    }

    @Test("Le prix exact du plafond retiré : la géométrie du Dock passe ici, et nulle part ailleurs")
    func lePrixDuPlafondRetire() {
        // C'est le coût, énoncé plutôt que caché : sans le plafond, le Dock, la barre du Window
        // Server et l'overlay de capture ont la même géométrie que NotchNook, et ce prédicat ne
        // les distingue pas. Ce qui les tient, c'est qu'ils n'atteignent JAMAIS ce chemin — il ne
        // se parcourt que sur un pid issu du catalogue, dont les deux portes les excluent : la
        // découverte par `estFenetreEncoche` (test `overlayPleinEcran`) et par `systemBundleIDs`,
        // l'amorçage par une liste de sept bundleIDs relevés dans un `Info.plist`.
        #expect(couvre(bounds(x: 619, y: 1440, w: 1352, h: 878)))
    }
}
