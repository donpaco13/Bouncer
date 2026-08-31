//
// NotchOverlay.swift — Milestone 2 : flèches ‹ › au survol de l'encoche, swipe deux doigts.
// Géométrie dérivée de `WindowManager.notchZone()` (source unique, cf. CLAUDE.md "zéro
// hardcoding d'encoche"). Le panel (NSPanel transparent) n'existe plus que pour porter ces
// flèches et leur donner une cible de clic : il est construit une seule fois puis ordonné à
// l'écran (`orderFrontRegardless()`) UNIQUEMENT pendant le survol de la zone d'encoche, et
// retiré (`orderOut(nil)`) dès que le curseur en sort. Hors survol, aucune fenêtre d'Island
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
// `windowManager.notchZone()` plutôt que de faire confiance au frame du panel, qui peut être
// hors écran (retiré) ou nil (pas encore construit / plus d'encoche détectée).

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

    /// (Re)positionne le panel sur la zone d'encoche actuelle. Pas d'encoche détectée -> pas de
    /// panel, pas de crash (appelé aussi au changement de configuration d'écrans).
    @objc private func rebuild() {
        guard let zone = windowManager.notchZone() else {
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
        p.ignoresMouseEvents = true // passthrough par défaut, cf. commentaire d'en-tête
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let arrows = NotchArrowsView(frame: NSRect(origin: .zero, size: zone.size))
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

    // Porte sur windowManager.notchZone() et non panel.frame : le panel peut être hors écran
    // (retiré hors survol) ou nil (pas d'encoche détectée) — cf. commentaire d'en-tête. Marge
    // verticale partagée : la zone d'encoche fait ~29pt de haut, difficile à survoler pile.
    private func isCursorOnNotch() -> Bool {
        guard let zone = windowManager.notchZone() else { return false }
        return zone.insetBy(dx: 0, dy: -6).contains(NSEvent.mouseLocation)
    }

    private func updateHover() {
        guard let panel else { return }
        let hovering = isCursorOnNotch()
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        panel.ignoresMouseEvents = !hovering
        arrowsView?.setVisible(hovering)
        if !hovering { swipeAccumulator = 0 }
    }

    private func handleScroll(_ event: NSEvent) {
        // `isHovering` est latché par le monitor `.mouseMoved` : il ne se remet pas à jour si le
        // curseur reste immobile pendant qu'une app d'encoche tierce déploie son panneau
        // par-dessus. On revérifie donc la position réelle du curseur ici plutôt que de faire
        // confiance à cet état.
        guard isCursorOnNotch(), Date() >= swipeGateUntil else { return }
        swipeAccumulator += event.scrollingDeltaX
        guard abs(swipeAccumulator) >= swipeThreshold else { return }
        // Swipe vers la gauche (deltaX négatif) -> app suivante ; vers la droite -> précédente.
        windowManager.cycle(forward: swipeAccumulator < 0)
        swipeAccumulator = 0
        swipeGateUntil = Date().addingTimeInterval(swipeCooldown)
    }
}

/// Flèches ‹ › aux bords de la zone d'encoche, invisibles par défaut, révélées au survol.
private final class NotchArrowsView: NSView {
    var onArrowClicked: ((_ forward: Bool) -> Void)?

    private let leftButton = NSButton()
    private let rightButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        for (button, symbol, forward) in [
            (leftButton, "chevron.left", false), (rightButton, "chevron.right", true),
        ] {
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .white
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
        leftButton.frame = NSRect(x: 2, y: y, width: size, height: size)
        rightButton.frame = NSRect(x: bounds.width - size - 2, y: y, width: size, height: size)
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
