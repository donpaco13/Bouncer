//
// NotchOverlay.swift — Milestone 2 : flèches ‹ › au survol de l'encoche, swipe deux doigts.
//
// Géométrie dérivée de `WindowManager.notchZone()` (source unique, cf. CLAUDE.md "zéro
// hardcoding d'encoche"), MAIS élargie : `notchZone()` décrit le boîtier caméra, c'est-à-dire la
// bande NON AFFICHABLE de la barre des menus. Y dessiner les flèches revenait à les cacher
// derrière le matériel, et y attendre le curseur revenait à demander de viser une cible
// invisible — mesuré : sur deux minutes d'usage réel, 342 événements de scroll et pas un seul
// avec le curseur dans cette bande. La zone sensible et le panel couvrent donc le boîtier PLUS
// `margeLaterale` points de chaque côté, pris sur les aires auxiliaires (les parties visibles de la
// barre des menus), et les flèches se logent dans ces marges. Calcul dans `zoneSurvol` /
// `abscissesFleches` (BouncerCore), verrouillé par `ZoneSurvolTests`.
//
// Le panel (NSPanel transparent) n'existe que pour porter ces flèches et leur donner une cible de
// clic : il est construit une seule fois puis ordonné à l'écran (`orderFrontRegardless()`)
// UNIQUEMENT pendant le survol de la zone, et retiré (`orderOut(nil)`) dès que le curseur en sort.
// Hors survol, aucune fenêtre de Bouncer ne recouvre l'encoche — un panel resté à l'écran en
// permanence, même transparent en théorie (`isOpaque = false`), masquait visuellement le logo
// replié des apps d'encoche tierces (constaté en réel avec Vibe Island) sans qu'on ait pu établir
// pourquoi la transparence ne s'appliquait pas ; plutôt que déboguer ça, on supprime le besoin.
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
import Combine
import BouncerCore

// `@MainActor` : ce contrôleur ne manipule que des NSPanel, NSView et monitors NSEvent, et
// `WindowManager` porte désormais la même isolation. Elle était déjà vraie à l'exécution.
@MainActor
final class NotchOverlayController: NSObject {
    private let windowManager: WindowManager
    /// Les préférences. Trois d'entre elles atterrissent ici : ce qui déclenche le cycle, la
    /// portée d'approche, la largeur des bandes latérales. La même instance que la fenêtre de
    /// réglages — c'est ce qui fait qu'un curseur qu'on bouge se voit à l'écran sans relancer.
    private let reglages: Reglages
    private var abonnement: AnyCancellable?
    private var abonnementApps: AnyCancellable?
    private var panel: NSPanel?
    private var arrowsView: NotchArrowsView?
    private var hoverMonitor: Any?
    private var scrollMonitor: Any?

    /// Zone sensible courante, calculée par `rebuild()`. Cf. commentaire d'en-tête : la relire à
    /// chaque événement souris coûtait une publication SwiftUI par mouvement.
    private var zoneSensible: CGRect?
    private var opaciteCourante: CGFloat = 0

    // `sideMargin` (44 pt) et `porteeApproche` (72 pt) étaient des constantes ici. La seconde
    // était la SEULE du projet restée réglée à l'œil, et les deux décident de la sensation du
    // geste : elles vivent désormais dans `Reglages`, avec ces mêmes valeurs en défaut.

    /// La session porte le détecteur ET sa durée de vie (cf. `SessionSwipe`) : c'est le
    /// remplacement du détecteur EN COURS DE GESTE qui produisait deux bascules pour un geste.
    private var session = SessionSwipe()

    /// Le cycle a-t-il au moins une cible ? Mis en cache et non redemandé à chaque événement :
    /// `cycleAUneCible` traverse `entreesMenu`, qui interroge LaunchServices pour chaque bundleID
    /// du catalogue, et `updateHover` tourne à chaque mouvement du curseur.
    ///
    /// Sans ça, décocher toutes les apps dans les réglages laissait les deux flèches s'allumer
    /// normalement au survol et ne RIEN faire au clic (`cycle` sort sur une liste vide). Un
    /// contrôle qui répond visuellement et n'agit pas est pire qu'un contrôle absent.
    private var cycleAUneCible = true

    init(windowManager: WindowManager, reglages: Reglages) {
        self.windowManager = windowManager
        self.reglages = reglages
        super.init()
        rebuild()
        // Un réglage qui ne se voit qu'au relancement n'est pas réglable : on ne peut pas tâtonner
        // une distance d'approche en redémarrant l'app entre deux essais. `rebuild()` recalcule la
        // géométrie et réapplique l'opacité, ce qui couvre les trois réglages d'un coup.
        abonnement = reglages.objectWillChange.sink { [weak self] in
            // `objectWillChange` part AVANT l'écriture de la nouvelle valeur : relire tout de
            // suite rendrait l'ancienne.
            Task { @MainActor in self?.rebuild() }
        }
        // Le contenu du cycle change sans que ni les réglages ni les écrans bougent : une app
        // d'encoche qu'on lance ou qu'on quitte suffit. Les flèches doivent suivre.
        abonnementApps = windowManager.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.majCycleAUneCible() }
        }
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

    /// Cadre du panel : le boîtier caméra élargi de `margeLaterale` de chaque côté. La zone SENSIBLE
    /// ajoute 6 pt en haut et en bas — la bande fait ~29 pt, difficile à survoler pile.
    private func cadrePanel() -> CGRect? {
        windowManager.notchZone().map { zoneSurvol(encoche: $0, marge: reglages.margeLaterale) }
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
            arrowsView?.margeLaterale = reglages.margeLaterale
        } else {
            buildPanel(zone: zone)
        }
        // Force le recalcul : `updateHover` sort tôt quand l'opacité n'a pas bougé, or ici c'est
        // la géométrie, le mode d'activation ou la liste des apps cochées qui vient de changer,
        // pas le curseur.
        cycleAUneCible = windowManager.cycleAUneCible
        opaciteCourante = -1
        updateHover()
    }

    /// Relit le cache et ne réveille l'affichage que si la réponse a changé.
    private func majCycleAUneCible() {
        let cible = windowManager.cycleAUneCible
        guard cible != cycleAUneCible else { return }
        cycleAUneCible = cible
        opaciteCourante = -1
        updateHover()
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

        let arrows = NotchArrowsView(frame: NSRect(origin: .zero, size: zone.size), margeLaterale: reglages.margeLaterale)
        arrows.onArrowClicked = { [weak self] forward in self?.windowManager.cycle(forward: forward) }
        p.contentView = arrows

        // Pas d'orderFrontRegardless() ici : le panel n'est ordonné à l'écran que pendant le
        // survol, piloté par updateHover() — cf. commentaire d'en-tête.
        panel = p
        arrowsView = arrows
        // Le monitor de scroll n'est PAS posé ici : il vit et meurt avec la présence du curseur
        // dans la zone (cf. `majMoniteurScroll`).
    }

    /// Attache ou détache le monitor de défilement.
    ///
    /// Il était attaché en permanence, et interceptait donc 100 % des défilements de la machine
    /// pour n'en utiliser qu'une poignée : `handleScroll` jette de toute façon tout ce qui arrive
    /// hors zone, et un seul geste produit 86 événements dont 72 d'inertie (audit de fluidité,
    /// `docs/PERFORMANCE.md`). La condition d'attache est donc exactement celle sous laquelle un
    /// événement pourrait compter — ni plus large, ni plus étroite.
    ///
    /// Le monitor reste GLOBAL, et ce n'est pas un détail : dès qu'une app d'encoche tierce
    /// déploie son panneau, sa fenêtre consomme le scroll avant nous, et un monitor local ne
    /// verrait plus rien (cf. commentaire d'en-tête). On change QUAND il écoute, jamais quoi.
    ///
    /// La condition ne se dérive PAS de l'opacité des flèches : en mode « swipe seul » elle vaut
    /// zéro en permanence, et le swipe ne marcherait plus du tout.
    private func majMoniteurScroll() {
        // `doitEcouter` garde le monitor attaché tant qu'un geste est en cours, même si le curseur
        // a débordé de la zone : c'est ce qui empêche de repartir d'un détecteur neuf au milieu
        // d'un mouvement, et donc d'en tirer une deuxième bascule (cf. `SessionSwipe`).
        // Rien à parcourir, rien à écouter : un swipe sur un cycle vide ne peut rien produire.
        let voulu = cycleAUneCible
            && session.doitEcouter(
                swipeActif: reglages.modeActivation.swipeActif,
                curseurDansLaZone: curseurDansLaZone()
            )
        if voulu, scrollMonitor == nil {
            session.demarre()
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
            }
        } else if !voulu, let m = scrollMonitor {
            NSEvent.removeMonitor(m)
            scrollMonitor = nil
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
        // AVANT la garde d'opacité : en mode « swipe seul » l'opacité vaut zéro en permanence, et
        // une garde placée plus haut empêcherait le monitor d'être jamais attaché.
        majMoniteurScroll()

        // Flèches désactivées : le panel ne va JAMAIS à l'écran, donc rien de Bouncer ne recouvre
        // la barre des menus. C'est la différence entre « invisible » et « absent », et c'est ce
        // que promet le mode « swipe seul ».
        // Deux raisons de ne rien montrer, et c'est la même : la flèche ne ferait rien. Le mode
        // « swipe seul », que l'utilisateur a choisi ; et un cycle sans aucune cible, parce qu'il
        // a tout décoché dans les réglages — `cycle` sort alors sur une liste vide.
        let opacite = (reglages.modeActivation.flechesActives && cycleAUneCible)
            ? opaciteFleches(curseur: NSEvent.mouseLocation, zone: zone, portee: reglages.porteeApproche)
            : 0
        guard opacite != opaciteCourante else { return }
        let etaitVisible = opaciteCourante > 0
        opaciteCourante = opacite

        if opacite > 0 {
            if !etaitVisible { panel.orderFrontRegardless() }
        } else {
            panel.orderOut(nil)
        }
        arrowsView?.opacite = opacite
    }

    private func handleScroll(_ event: NSEvent) {
        // Pas de garde sur le mode ici : le monitor n'est simplement pas attaché quand le swipe
        // est désactivé (`majMoniteurScroll`). Une seule condition, un seul endroit.
        // La position du curseur est revérifiée ici plutôt que déduite d'un état latché par le
        // monitor `.mouseMoved` : celui-ci ne se remet pas à jour si le curseur reste immobile
        // pendant qu'une app d'encoche tierce déploie son panneau par-dessus.
        let phase = phaseGeste(event)
        let decision = session.recoit(
            EvenementDefilement(
                phase: phase,
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
        // Le geste vient de finir : si le curseur avait débordé de la zone, c'est ici qu'on peut
        // enfin détacher le monitor. Sinon il resterait attaché jusqu'au prochain mouvement de
        // souris, ce qui rendrait à moitié l'économie de `majMoniteurScroll`. Différé d'un tour de
        // boucle : on est DANS le bloc du monitor, et `removeMonitor` le libérerait sous ses pieds.
        if case .fin = phase {
            Task { @MainActor [weak self] in self?.majMoniteurScroll() }
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
    /// où le boîtier caméra les cacherait. Variable, parce qu'elle est réglable et que le panel
    /// est construit une seule fois puis repositionné.
    var margeLaterale: CGFloat {
        didSet { layoutArrows() }
    }

    init(frame frameRect: NSRect, margeLaterale: CGFloat) {
        self.margeLaterale = margeLaterale
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
        let x = abscissesFleches(largeurOverlay: bounds.width, marge: margeLaterale, taille: size)
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
