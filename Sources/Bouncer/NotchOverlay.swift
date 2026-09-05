//
// NotchOverlay.swift — Milestone 2 : flèches ‹ › au survol de l'encoche, swipe deux doigts.
//
// Géométrie dérivée de `WindowManager.notchZone()` (source unique, cf. CLAUDE.md "zéro
// hardcoding d'encoche"), MAIS élargie : `notchZone()` décrit le boîtier caméra, c'est-à-dire la
// bande NON AFFICHABLE de la barre des menus. Y dessiner les flèches revenait à les cacher
// derrière le matériel, et y attendre le curseur revenait à demander de viser une cible
// invisible — mesuré : sur deux minutes d'usage réel, 342 événements de scroll et pas un seul
// avec le curseur dans cette bande. La zone sensible et le panel couvrent donc le boîtier PLUS
// `sideMargin` points de chaque côté, pris sur les aires auxiliaires (les parties visibles de la
// barre des menus), et les flèches se logent dans ces marges. Calcul dans `zoneSurvol` /
// `abscissesFleches` (BouncerCore), verrouillé par `ZoneSurvolTests`.
//
// Le panel (NSPanel transparent) n'existe que pour porter ces flèches et leur donner une cible de
// clic : il est construit une seule fois puis ordonné à l'écran (`orderFrontRegardless()`)
// UNIQUEMENT pendant le survol de la zone, et retiré (`orderOut(nil)`) dès que le curseur en sort. Hors survol, aucune fenêtre d'Island
// Switch ne recouvre l'encoche — un panel resté à l'écran en permanence, même transparent en
// théorie (`isOpaque = false`), masquait visuellement le logo replié des apps d'encoche
// tierces (constaté en réel avec Vibe Island) sans qu'on ait pu établir pourquoi la
// transparence ne s'appliquait pas ; plutôt que déboguer ça, on supprime le besoin.
//
// Le survol est détecté par un monitor GLOBAL (`.mouseMoved`) : tant que le panel n'est pas à
// l'écran (ou que `ignoresMouseEvents = true`), il ne reçoit RIEN — un monitor local ne
// verrait donc jamais l'entrée dans la zone. Le scroll est capté par un monitor GLOBAL aussi
// (`.scrollWheel`) : un monitor local ne voit que les événements que macOS a déjà remis à notre
// app, or dès qu'une app d'encoche tierce (Vibe Island, boringNotch…) déploie son panneau, sa
// fenêtre consomme le scroll avant nous, même quand notre panel est à l'écran. Le monitor
// global observe l'événement quel que soit qui le consomme ensuite — c'est pour ça que
// `handleScroll` et `updateHover` revérifient la position du curseur directement via
// `zoneSensible` plutôt que de faire confiance au frame du panel, qui peut être hors écran
// (retiré) ou nil (pas encore construit / plus d'encoche détectée).
//
// MESURÉ le 2026-09-03 sur la machine de référence, en capturant un geste réel à travers ce même
// monitor global : le repère est bien celui annoncé (NSEvent.mouseLocation et zoneEncoche() sont
// à l'écart vertical 0,0 pt), le monitor voit bien les 86 événements du geste avec le curseur
// dans la bande — donc ni le repère ni le plumbing n'étaient en cause. Ce qui l'était : la
// traîne d'INERTIE, 72 événements sur 1,32 s après que les doigts ont quitté la surface, comptée
// comme du geste. Un geste produisait deux bascules (+0,025 s puis +0,622 s). La décision vit
// désormais dans `DetecteurSwipe` (BouncerCore), rejouable en test sur ce flux enregistré.
//
// La zone est CALCULÉE UNE FOIS par `rebuild()` et gardée, pas redemandée à chaque événement :
// `notchZone()` écrit dans un `@Published`, et l'appeler depuis un monitor `.mouseMoved` faisait
// publier SwiftUI des centaines de fois par seconde pour une valeur qui ne change qu'au
// changement de configuration d'écrans — le seul moment où `rebuild()` tourne.

import AppKit
import BouncerCore

// `@MainActor` : ce contrôleur ne manipule que des NSPanel, NSView et monitors NSEvent, et
// `WindowManager` porte désormais la même isolation. Elle était déjà vraie à l'exécution.
@MainActor
final class NotchOverlayController: NSObject {
    private let windowManager: WindowManager
    private var panel: NSPanel?
    private var arrowsView: NotchArrowsView?
    private var hoverMonitor: Any?
    private var scrollMonitor: Any?

    /// Zone sensible courante, calculée par `rebuild()`. Cf. commentaire d'en-tête : la relire à
    /// chaque événement souris coûtait une publication SwiftUI par mouvement.
    private var zoneSensible: CGRect?
    private var opaciteCourante: CGFloat = 0

    /// Largeur de bande visible prise de chaque côté du boîtier caméra — assez pour loger une
    /// flèche et lui donner une cible de clic atteignable, assez peu pour ne pas s'étaler sur les
    /// menus. Cf. commentaire d'en-tête.
    private let sideMargin: CGFloat = 44

    /// Distance à laquelle les flèches commencent à apparaître, au-delà de la zone sensible.
    /// SEULE CONSTANTE DE CE CORRECTIF QUI RESTE AU JUGÉ : la bande fait 41 pt de haut, 72 pt
    /// donne une rampe encore perceptible à vitesse de pointeur normale sans allumer les flèches
    /// dès qu'on longe le haut de l'écran. À régler au retour de test réel.
    private let porteeApproche: CGFloat = 72

    private var detecteur = DetecteurSwipe()

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        super.init()
        rebuild()
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateHover()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    deinit {
        if let m = hoverMonitor { NSEvent.removeMonitor(m) }
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
    }

    /// Cadre du panel : le boîtier caméra élargi de `sideMargin` de chaque côté. La zone SENSIBLE
    /// ajoute 6 pt en haut et en bas — la bande fait ~29 pt, difficile à survoler pile.
    private func cadrePanel() -> CGRect? {
        windowManager.notchZone().map { zoneSurvol(encoche: $0, marge: sideMargin) }
    }

    /// (Re)positionne le panel sur la zone actuelle. Pas d'encoche détectée -> pas de
    /// panel, pas de crash (appelé aussi au changement de configuration d'écrans).
    @objc private func rebuild() {
        guard let zone = cadrePanel() else {
            zoneSensible = nil
            teardownPanel()
            return
        }
        zoneSensible = zone.insetBy(dx: 0, dy: -6)
        if let panel {
            panel.setFrame(zone, display: true)
            arrowsView?.frame = NSRect(origin: .zero, size: zone.size)
        } else {
            buildPanel(zone: zone)
        }
    }

    private func teardownPanel() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
        arrowsView = nil
        opaciteCourante = 0
    }

    private func buildPanel(zone: CGRect) {
        let p = NSPanel(
            contentRect: zone,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // .statusBar + 1 (niveau 26) ne suffit PAS : mesuré en réel, Vibe Island et boringNotch
        // tournent au niveau CGWindowList 27 (kCGWindowLayer) — juste au-dessus. Sans marge plus
        // large, leurs fenêtres captent le clic/scroll avant notre panel. Marge de +10 pour rester
        // au-dessus de variations similaires sans grimper jusqu'à popUpMenu(101)/screenSaver(1000).
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        // Pas de `ignoresMouseEvents` : le panel n'est à l'écran que pendant le survol, et sa vue
        // ne retient que les clics sur les flèches (`hitTest`) — le reste de la bande, menus et
        // icônes de statut compris, reste cliquable normalement.
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let arrows = NotchArrowsView(frame: NSRect(origin: .zero, size: zone.size), sideMargin: sideMargin)
        arrows.onArrowClicked = { [weak self] forward in self?.windowManager.cycle(forward: forward) }
        p.contentView = arrows

        // Pas d'orderFrontRegardless() ici : le panel n'est ordonné à l'écran que pendant le
        // survol, piloté par updateHover() — cf. commentaire d'en-tête.
        panel = p
        arrowsView = arrows

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }
    }

    private func curseurDansLaZone() -> Bool {
        zoneSensible?.contains(NSEvent.mouseLocation) ?? false
    }

    /// Les flèches se révèlent À L'APPROCHE et non au survol : l'opacité suit la distance du
    /// curseur à la zone. Le panel n'est à l'écran que tant qu'elles sont visibles — hors de la
    /// portée, on le retire, ce que l'en-tête explique.
    private func updateHover() {
        guard let panel, let zone = zoneSensible else { return }
        let opacite = opaciteFleches(curseur: NSEvent.mouseLocation, zone: zone, portee: porteeApproche)
        guard opacite != opaciteCourante else { return }
        let etaitVisible = opaciteCourante > 0
        opaciteCourante = opacite

        if opacite > 0 {
            if !etaitVisible { panel.orderFrontRegardless() }
        } else {
            panel.orderOut(nil)
            detecteur.reinitialise()
        }
        arrowsView?.opacite = opacite
    }

    private func handleScroll(_ event: NSEvent) {
        // La position du curseur est revérifiée ici plutôt que déduite d'un état latché par le
        // monitor `.mouseMoved` : celui-ci ne se remet pas à jour si le curseur reste immobile
        // pendant qu'une app d'encoche tierce déploie son panneau par-dessus.
        let decision = detecteur.recoit(
            EvenementDefilement(
                phase: phaseGeste(event),
                inertie: event.momentumPhase != [],
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                instant: event.timestamp,
                dansLaZone: curseurDansLaZone()
            )
        )
        // Toujours `forward: true` : un swipe horizontal avance d'un cran, quel que soit son
        // sens, et le refaire du même côté continue de faire tourner le cycle. C'est `cycle` qui
        // reboucle, il n'y a donc pas de cul-de-sac. Le sens reste porté par les deux flèches, où
        // il est lisible ; dans un geste, il ne l'est pas — il faut le retenir, et il ne se
        // retient pas (retour de test réel du 2026-09-05).
        if case .bascule = decision {
            windowManager.cycle(forward: true)
        }
    }

    /// `NSEvent.Phase` -> phase de geste. Un périphérique sans phase (molette classique) tombe
    /// dans `aucune`, où le détecteur retombe sur sa fenêtre de repos temporelle.
    private func phaseGeste(_ event: NSEvent) -> EvenementDefilement.Phase {
        let p = event.phase
        if p.contains(.began) { return .debut }
        if p.contains(.changed) { return .encours }
        if p.contains(.ended) || p.contains(.cancelled) { return .fin }
        return .aucune
    }
}

/// Flèches ‹ › de part et d'autre du boîtier caméra, invisibles par défaut, révélées à l'approche.
private final class NotchArrowsView: NSView {
    var onArrowClicked: ((_ forward: Bool) -> Void)?

    private let leftButton = NSButton()
    private let rightButton = NSButton()
    /// Largeur de la bande visible à chaque extrémité : les flèches s'y centrent, jamais au milieu
    /// où le boîtier caméra les cacherait.
    private let sideMargin: CGFloat

    init(frame frameRect: NSRect, sideMargin: CGFloat) {
        self.sideMargin = sideMargin
        super.init(frame: frameRect)
        wantsLayer = true

        for (button, symbol, forward) in [
            (leftButton, "chevron.left", false), (rightButton, "chevron.right", true),
        ] {
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            button.imageScaling = .scaleProportionallyDown
            // Glyphe blanc sur pastille sombre — cf. `Self.fondPastille` : le fond de nos flèches
            // nous appartient, donc le contraste ne dépend plus de ce qu'une app tierce dessine
            // dessous.
            button.contentTintColor = .white
            button.wantsLayer = true
            button.layer?.backgroundColor = Self.fondPastille
            button.target = self
            button.tag = forward ? 1 : 0
            button.action = #selector(arrowTapped(_:))
            button.alphaValue = 0
            addSubview(button)
        }
        layoutArrows()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }

    override func layout() {
        super.layout()
        layoutArrows()
    }

    /// Fond de la pastille. MESURÉ le 2026-09-05 : la fenêtre de boringNotch fait 640 pt de large
    /// (975→1615 sur la machine de référence) alors que le boîtier caméra n'en fait que 166
    /// (1212→1378) — elle recouvre donc INTÉGRALEMENT les deux marges de 44 pt où logent nos
    /// flèches. Ce n'est pas un problème de z-order : notre panel est ordonné au niveau 35 et le
    /// relevé `CGWindowList` le donne bien devant boringNotch (27) et Vibe Island (27). Nos flèches
    /// sont donc DEVANT, mais dessinées par-dessus une surface qui ne nous appartient pas et dont
    /// on ne sait rien : noir de l'encoche déployée, pochette d'album, visualiseur. Un glyphe
    /// monochrome y disparaît, quelle que soit la couleur choisie — d'où la pastille : elle rend
    /// les 22 pt sous le chevron prévisibles, et le blanc redevient lisible partout.
    private static let fondPastille = NSColor.black.withAlphaComponent(0.55).cgColor

    private func layoutArrows() {
        // 22 pt et non 14 : la pastille doit rester lisible sur une pochette d'album, et une cible
        // de clic de 14 pt dans une marge de 44 était petite pour rien.
        let size = min(bounds.height - 4, 22)
        let y = (bounds.height - size) / 2
        let x = abscissesFleches(largeurOverlay: bounds.width, marge: sideMargin, taille: size)
        leftButton.frame = NSRect(x: x.gauche, y: y, width: size, height: size)
        rightButton.frame = NSRect(x: x.droite, y: y, width: size, height: size)
        for button in [leftButton, rightButton] {
            button.layer?.cornerRadius = size / 2
        }
    }

    /// Le panel couvre une portion de barre des menus dès l'approche : sans ce passe-plat, il
    /// avalerait les clics sur les menus et les icônes de statut qui s'y trouvent. Seuls les deux
    /// boutons répondent, et seulement une fois franchement visibles — une flèche à 10 %
    /// d'opacité est une cible qu'on ne voit pas, donc qu'on ne vise pas volontairement.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard opacite >= 0.5 else { return nil }
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    @objc private func arrowTapped(_ sender: NSButton) {
        onArrowClicked?(sender.tag == 1)
    }

    /// Le fondu, c'est cette rampe : elle suit la distance du curseur, donc la main. Pas
    /// d'animation de durée fixe — elle se battrait contre le mouvement au lieu de l'accompagner,
    /// et sur un aller-retour rapide au bord de la zone elle traînerait derrière le curseur.
    var opacite: CGFloat = 0 {
        didSet {
            leftButton.alphaValue = opacite
            rightButton.alphaValue = opacite
        }
    }
}
