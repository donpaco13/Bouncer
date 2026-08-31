//
// NotchOverlay.swift — Milestone 2 : overlay sur l'encoche (NSPanel), swipe 2 doigts, flèches
// au survol. Géométrie dérivée de `WindowManager.notchZone()` (source unique, cf. CLAUDE.md
// "zéro hardcoding d'encoche"). Ne devient interactif (`ignoresMouseEvents = false`) que
// pendant le survol de la zone d'encoche ; le reste du temps les clics passent aux fenêtres
// dessous.
//
// Le survol est détecté par un monitor GLOBAL (`.mouseMoved`) : tant que
// `ignoresMouseEvents = true`, le panel ne reçoit RIEN (ni move, ni scroll) — un monitor local
// ne verrait donc jamais l'entrée dans la zone. Une fois `ignoresMouseEvents = false`, le
// monitor local de `.scrollWheel` (posé une fois, actif seulement quand le panel reçoit
// effectivement les événements) capte le swipe.

import AppKit

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

        p.orderFrontRegardless()
        panel = p
        arrowsView = arrows

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func updateHover() {
        guard let panel else { return }
        // Marge verticale : la zone d'encoche fait ~29pt de haut, difficile à survoler pile.
        let hovering = panel.frame.insetBy(dx: 0, dy: -6).contains(NSEvent.mouseLocation)
        guard hovering != isHovering else { return }
        isHovering = hovering
        panel.ignoresMouseEvents = !hovering
        arrowsView?.setVisible(hovering)
        if !hovering { swipeAccumulator = 0 }
    }

    private func handleScroll(_ event: NSEvent) {
        guard isHovering, Date() >= swipeGateUntil else { return }
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
