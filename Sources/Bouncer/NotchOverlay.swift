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
// `overlayZone()` plutôt que de faire confiance au frame du panel, qui peut être hors écran
// (retiré) ou nil (pas encore construit / plus d'encoche détectée).

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

    private var isHovering = false

    /// Largeur de bande visible prise de chaque côté du boîtier caméra — assez pour loger une
    /// flèche et lui donner une cible de clic atteignable, assez peu pour ne pas s'étaler sur les
    /// menus. Cf. commentaire d'en-tête.
    private let sideMargin: CGFloat = 44

    // Anti-rebond swipe : une rafale de scrollWheel (un seul geste physique) ne doit produire
    // qu'UNE bascule. On accumule deltaX jusqu'au seuil, puis on ferme la porte le temps du
    // cooldown — le reste de la rafale tombe pendant cette fenêtre.
    private var swipeAccumulator: CGFloat = 0
    private var swipeGateUntil: Date = .distantPast
    private let swipeThreshold: CGFloat = 12
    private let swipeCooldown: TimeInterval = 0.5

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

    /// Zone sensible et cadre du panel : le boîtier caméra élargi de `sideMargin` de chaque côté.
    private func overlayZone() -> CGRect? {
        windowManager.notchZone().map { zoneSurvol(encoche: $0, marge: sideMargin) }
    }

    /// (Re)positionne le panel sur la zone actuelle. Pas d'encoche détectée -> pas de
    /// panel, pas de crash (appelé aussi au changement de configuration d'écrans).
    @objc private func rebuild() {
        guard let zone = overlayZone() else {
            teardownPanel()
            return
        }
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
        isHovering = false
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

    // Porte sur overlayZone() et non panel.frame : le panel peut être hors écran (retiré hors
    // survol) ou nil (pas d'encoche détectée) — cf. commentaire d'en-tête. Marge verticale
    // partagée : la bande fait ~29pt de haut, difficile à survoler pile.
    private func isCursorOnOverlay() -> Bool {
        guard let zone = overlayZone() else { return false }
        return zone.insetBy(dx: 0, dy: -6).contains(NSEvent.mouseLocation)
    }

    private func updateHover() {
        guard let panel else { return }
        let hovering = isCursorOnOverlay()
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        arrowsView?.setVisible(hovering)
        if !hovering { swipeAccumulator = 0 }
    }

    private func handleScroll(_ event: NSEvent) {
        // `isHovering` est latché par le monitor `.mouseMoved` : il ne se remet pas à jour si le
        // curseur reste immobile pendant qu'une app d'encoche tierce déploie son panneau
        // par-dessus. On revérifie donc la position réelle du curseur ici plutôt que de faire
        // confiance à cet état.
        guard isCursorOnOverlay(), Date() >= swipeGateUntil else { return }
        swipeAccumulator += event.scrollingDeltaX
        guard abs(swipeAccumulator) >= swipeThreshold else { return }
        // Swipe vers la gauche (deltaX négatif) -> app suivante ; vers la droite -> précédente.
        windowManager.cycle(forward: swipeAccumulator < 0)
        swipeAccumulator = 0
        swipeGateUntil = Date().addingTimeInterval(swipeCooldown)
    }
}

/// Flèches ‹ › de part et d'autre du boîtier caméra, invisibles par défaut, révélées au survol.
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
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imageScaling = .scaleProportionallyDown
            // `.labelColor` et pas blanc : les flèches ne sont plus sur le noir du boîtier mais
            // sur la barre des menus, qui suit l'apparence système — du blanc y disparaît en clair.
            button.contentTintColor = .labelColor
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

    private func layoutArrows() {
        let size = min(bounds.height - 4, 14)
        let y = (bounds.height - size) / 2
        let x = abscissesFleches(largeurOverlay: bounds.width, marge: sideMargin, taille: size)
        leftButton.frame = NSRect(x: x.gauche, y: y, width: size, height: size)
        rightButton.frame = NSRect(x: x.droite, y: y, width: size, height: size)
    }

    /// Le panel couvre une portion de barre des menus pendant le survol : sans ce passe-plat, il
    /// avalerait les clics sur les menus et les icônes de statut qui s'y trouvent. Seuls les deux
    /// boutons répondent, le reste de la surface se comporte comme si le panel n'était pas là.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    @objc private func arrowTapped(_ sender: NSButton) {
        onArrowClicked?(sender.tag == 1)
    }

    func setVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            leftButton.animator().alphaValue = visible ? 1 : 0
            rightButton.animator().alphaValue = visible ? 1 : 0
        }
    }
}
