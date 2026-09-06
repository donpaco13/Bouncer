//
// NotchOverlay.swift — Milestone 2 : flèches ‹ › au survol de l'encoche, swipe deux doigts.
//
// MESURÉ le 2026-09-05, et c'est la cause des swipes ratés que remontait le test réel. La zone
// écoutée faisait 254×41 pt ; la fenêtre que l'utilisateur VOIT et vise fait 640×210 pt
// (boringNotch) ou 740×520 pt (Vibe Island) — soit 2,7 % de la surface visible réellement
// sensible. Rejoué à travers ce pipeline : un geste posé sur l'île à 180 pt à droite de la bande
// est rejeté 13 fois par le garde `horsZone` ; un geste posé 80 pt sous la barre des menus ne
// laisse AUCUNE trace, le monitor de scroll n'étant même pas attaché. La géométrie se cale
// désormais sur la fenêtre réellement présente (`zoneSwipe`, BouncerCore), et le journal
// `TraceSwipe` note par quel garde chaque événement est tombé — sans quoi un swipe raté est un
// silence, et un silence ne se débogue pas.
//
// ET CE N'EST PAS LA MÊME ZONE QUE CELLE DES FLÈCHES, depuis que les avoir confondues a coûté deux
// régressions (QA du 2026-09-05, `docs/rapport-qa-round-2.html`). Elles n'ont pas les mêmes
// contraintes : un CLIC doit être précis et il se pose sur une fenêtre qui recouvre la barre des
// menus, donc la bande des flèches reste collée au boîtier, là où la mesure montre du dégagement ;
// un GESTE ne recouvre rien, donc sa zone peut suivre l'île en largeur — bornée en hauteur, sans
// quoi elle avale les défilements horizontaux ordinaires. Les deux calculs vivent côte à côte dans
// BouncerCore (`zoneSurvol` / `zoneSwipe`), chacun avec le relevé qui le fonde.
//
// Géométrie dérivée de `WindowManager.notchZone()` (source unique, cf. CLAUDE.md "zéro
// hardcoding d'encoche"), MAIS élargie : `notchZone()` décrit le boîtier caméra, c'est-à-dire la
// bande NON AFFICHABLE de la barre des menus. Y dessiner les flèches revenait à les cacher
// derrière le matériel, et y attendre le curseur revenait à demander de viser une cible
// invisible — mesuré : sur deux minutes d'usage réel, 342 événements de scroll et pas un seul
// avec le curseur dans cette bande. Le panel couvre donc le boîtier PLUS `margeLaterale` points
// de chaque côté en X, et les flèches se logent dans ces marges.
//
// EN Y, LE PANEL VIT UNE RANGÉE SOUS LA BARRE DES MENUS, et c'est le correctif du 2026-09-06.
// L'idée qu'il restait des marges « libres » dans la barre était fausse : la moitié droite l'était
// (les icônes de statut sont alignées à droite et macOS les arrête au boîtier), la gauche jamais —
// les TITRES de menus appartiennent à l'app au premier plan et leur emprise change avec elle
// (relevés `kAXMenuBar` : Munder Difflin 362, Finder 489, Arc 819 sur le même écran de 1352). Un
// panel posé dans cette rangée volait le clic de « Window » à gauche et de « Help » à droite, à
// toutes les marges du domaine. Le raisonnement complet, les relevés et le choix de borner en Y
// plutôt qu'en X vivent dans `bandeFleches` (BouncerCore) ; `BarreDesMenusTests` le verrouille.
// Calcul dans `zoneSurvol` / `bandeFleches` / `abscissesFleches` (BouncerCore).
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

    /// Dernier cadre de fenêtre d'encoche sur lequel la géométrie a été calée. Comparé à chaque
    /// publication de `WindowManager` : reconstruire l'overlay à chaque tour de timer pour un
    /// cadre identique ferait clignoter le panel deux fois par seconde.
    private var cadreFenetreSuivi: CGRect?

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
        // Deux choses suivies ici, et pour la même raison : ni les réglages ni les écrans ne
        // bougent quand une app d'encoche se lance ou se quitte, or ça change ET le contenu du
        // cycle ET l'emprise sur laquelle la géométrie se cale.
        abonnementApps = windowManager.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.majSuiviApps() }
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

    /// La fenêtre d'encoche à prendre en compte, ou `nil` si l'utilisateur a choisi de se caler
    /// sur le boîtier seul (ou qu'aucune app d'encoche n'est à l'écran).
    private func fenetreDeReference() -> CGRect? {
        reglages.ancrageZone == .fenetreEncoche ? windowManager.cadreFenetresEncoche : nil
    }

    /// Cadre du panel : de quoi loger une flèche de part et d'autre du BOÎTIER, une rangée SOUS
    /// la barre des menus.
    ///
    /// Le panel est une vraie fenêtre au niveau `statusBar + 10` : tout ce qu'il couvre, il peut
    /// le voler. Il n'y a AUCUNE portion de la rangée de la barre des menus dont on puisse dire
    /// qu'elle est libre — l'emprise des titres de menus appartient à l'app au premier plan et
    /// change avec elle (Munder Difflin 362, Finder 489, Arc 819 sur le même écran), les icônes
    /// de statut tiennent l'autre bout. Le panel sort donc de la rangée, ce qui règle les deux
    /// côtés d'un coup et sans rien avoir à relire. Le raisonnement complet et les relevés vivent
    /// dans `bandeFleches` (BouncerCore), où un test les regarde.
    ///
    /// La zone ÉCOUTÉE, elle, part de la rangée (`zoneSurvol`) et suit la fenêtre en largeur
    /// (`zoneSwipe`) : c'est un test géométrique, pas une fenêtre, donc l'agrandir ne recouvre
    /// rien et ne vole rien.
    private func cadrePanel() -> CGRect? {
        bandeSurvol().map { bandeFleches(survol: $0) }
    }

    /// La bande de référence, à hauteur de barre des menus : c'est d'elle que part la zone écoutée
    /// (`zoneSwipe`), et le panel s'en déduit en descendant d'une rangée.
    private func bandeSurvol() -> CGRect? {
        guard let (encoche, _, _) = zoneEncoche() else { return nil }
        return zoneSurvol(encoche: encoche, marge: reglages.margeLaterale)
    }

    /// (Re)positionne le panel sur la zone actuelle. Pas d'encoche détectée -> pas de
    /// panel, pas de crash (appelé aussi au changement de configuration d'écrans).
    @objc private func rebuild() {
        guard let survol = bandeSurvol() else {
            zoneSensible = nil
            teardownPanel()
            return
        }
        let zone = bandeFleches(survol: survol)
        zoneSensible = zoneSwipe(bande: survol, fenetre: fenetreDeReference())
        if let panel {
            panel.setFrame(zone, display: true)
            arrowsView?.frame = NSRect(origin: .zero, size: zone.size)
            arrowsView?.margeLaterale = reglages.margeLaterale
        } else {
            buildPanel(zone: zone)
        }
        arrowsView?.retrait = reglages.retraitFleches
        // La pastille sombre n'est pas un parti pris graphique, c'est un correctif de contraste :
        // elle n'a de raison d'être que si la flèche est dessinée PAR-DESSUS la fenêtre d'une app
        // tierce, dont on ne sait rien (noir de l'île, pochette d'album, visualiseur). Calées sur
        // le boîtier, les flèches retombent dessus dès que l'île est plus large que le boîtier,
        // c'est-à-dire presque toujours — la pastille est donc la règle, pas l'exception. Elle
        // reste conditionnée à la géométrie et non au réglage : c'est le recouvrement réel qui
        // décide.
        arrowsView?.pastilleNecessaire = flechesPoseesSurUneAppTierce(cadre: zone)
        // Force le recalcul : `updateHover` sort tôt quand l'opacité n'a pas bougé, or ici c'est
        // la géométrie, le mode d'activation ou la liste des apps cochées qui vient de changer,
        // pas le curseur.
        cycleAUneCible = windowManager.cycleAUneCible
        cadreFenetreSuivi = windowManager.cadreFenetresEncoche
        opaciteCourante = -1
        updateHover()
    }

    /// Une flèche tombe-t-elle SUR la fenêtre d'une app d'encoche ?
    ///
    /// La question ne se pose pas au réglage d'ancrage mais à la géométrie : c'est le
    /// recouvrement réel qui décide, et il reste possible en mode « boîtier », ou avec une fenêtre
    /// assez large pour que les flèches retombent dessus malgré le calage. Le contraste ne nous
    /// appartient plus dans ce cas-là — la pastille revient (cf. `NotchArrowsView.fondPastille`).
    private func flechesPoseesSurUneAppTierce(cadre: CGRect) -> Bool {
        guard let fenetre = windowManager.cadreFenetresEncoche, let vue = arrowsView else { return false }
        let taille = vue.tailleFleche
        let x = abscissesFleches(largeurOverlay: cadre.width, marge: reglages.margeLaterale, taille: taille)
        return [x.gauche, x.droite].contains { abscisse in
            fenetre.intersects(CGRect(x: cadre.minX + abscisse, y: cadre.minY, width: taille, height: cadre.height))
        }
    }

    /// Relit les deux caches et ne réveille l'affichage que si l'un d'eux a changé.
    ///
    /// Le cadre suivi est le cadre MESURÉ (`cadreFenetresEncoche`), jamais celui que filtre le
    /// réglage d'ancrage : en ancrage « boîtier seul », `fenetreDeReference()` rend `nil` en
    /// permanence, donc plus aucun changement de fenêtre ne passait cette garde — alors que
    /// `flechesPoseesSurUneAppTierce` lit le cadre mesuré, lui, et que la pastille de contraste
    /// en dépend. Elle restait périmée jusqu'au prochain changement de réglage ou d'écran (défaut
    /// R4 de la QA du 2026-09-06). Une garde ne peut pas surveiller une source et en rafraîchir
    /// une autre.
    private func majSuiviApps() {
        let cible = windowManager.cycleAUneCible
        let cadre = windowManager.cadreFenetresEncoche
        guard cible != cycleAUneCible || cadre != cadreFenetreSuivi else { return }
        cycleAUneCible = cible
        cadreFenetreSuivi = cadre
        // La géométrie a pu changer : c'est `rebuild` qui repositionne le panel, pas `updateHover`.
        rebuild()
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
        // ne retient que les clics sur les flèches (`hitTest`) — le reste de la bande reste
        // cliquable normalement. Cette promesse a été cassée une fois, quand le panel s'est mis à
        // faire 768 pt et à poser ses chevrons sur les icônes de statut : ce n'est pas `hitTest`
        // qui l'a rompue, c'est la géométrie. Et `hitTest` ne pouvait rien pour la moitié gauche
        // du même défaut — un curseur posé sur « Window » est DANS le panel, donc l'opacité de
        // révélation vaut 1,00 et le bouton prend le clic. Elle tient maintenant parce que le
        // panel a quitté la rangée de la barre des menus (cf. `bandeFleches`, BouncerCore).
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
            TraceSwipe.note("monitor", "attache", "curseur=\(NSEvent.mouseLocation)",
                            "zone=\(zoneSensible.map(String.init(describing:)) ?? "nil")")
        } else if !voulu, let m = scrollMonitor {
            NSEvent.removeMonitor(m)
            scrollMonitor = nil
            TraceSwipe.note("monitor", "detache",
                            "cycleAUneCible=\(cycleAUneCible)", "dansLaZone=\(curseurDansLaZone())",
                            "gesteEnCours=\(session.gesteEnCours)", "curseur=\(NSEvent.mouseLocation)")
        }
    }

    /// Bord montant de l'entrée dans la zone sensible, pour ne réveiller le sondage qu'une fois
    /// par approche et non à chaque événement souris.
    private var curseurEtaitDansLaZone = false

    private func curseurDansLaZone() -> Bool {
        zoneSensible?.contains(NSEvent.mouseLocation) ?? false
    }

    /// Les flèches se révèlent À L'APPROCHE et non au survol : l'opacité suit la distance du
    /// curseur à la zone. Le panel n'est à l'écran que tant qu'elles sont visibles — hors de la
    /// portée, on le retire, ce que l'en-tête explique.
    private func updateHover() {
        guard let panel, zoneSensible != nil else { return }
        // AVANT la garde d'opacité : en mode « swipe seul » l'opacité vaut zéro en permanence, et
        // une garde placée plus haut empêcherait le monitor d'être jamais attaché.
        majMoniteurScroll()

        // Le curseur qui entre dans la zone est le signal le plus sûr que l'utilisateur va agir,
        // et c'est le seul que le système ne poste nulle part : une app d'encoche qui détruit sa
        // fenêtre sans quitter son process n'émet aucune notification, seul le sondage la voit.
        // On resonde donc au bord montant — une fois par entrée, pas à chaque pixel parcouru.
        let dansLaZone = curseurDansLaZone()
        if dansLaZone, !curseurEtaitDansLaZone { windowManager.reveiller() }
        curseurEtaitDansLaZone = dansLaZone

        // Flèches désactivées : le panel ne va JAMAIS à l'écran, donc rien de Bouncer ne recouvre
        // la barre des menus. C'est la différence entre « invisible » et « absent », et c'est ce
        // que promet le mode « swipe seul ».
        // Deux raisons de ne rien montrer, et c'est la même : la flèche ne ferait rien. Le mode
        // « swipe seul », que l'utilisateur a choisi ; et un cycle sans aucune cible, parce qu'il
        // a tout décoché dans les réglages — `cycle` sort alors sur une liste vide.
        // La progression se mesure à la BANDE des flèches, pas à la zone de swipe : celle-ci
        // descend jusqu'en bas de l'île déployée, et les flèches s'allumeraient dès qu'on passe
        // sous l'encoche, loin d'elles.
        let progression = (reglages.modeActivation.flechesActives && cycleAUneCible)
            ? opaciteFleches(curseur: NSEvent.mouseLocation, zone: panel.frame,
                             portee: reglages.porteeApproche)
            : 0
        guard progression != opaciteCourante else { return }
        let etaitVisible = opaciteCourante > 0
        opaciteCourante = progression

        if progression > 0 {
            if !etaitVisible { panel.orderFrontRegardless() }
        } else {
            panel.orderOut(nil)
        }
        let r = revelationFleches(progression: progression, retrait: reglages.retraitFleches)
        arrowsView?.revelation = r
        TraceSwipe.note("survol", "progression=\(String(format: "%.2f", progression))",
                        "opacite=\(String(format: "%.2f", r.opacite))",
                        "decalage=\(String(format: "%.1f", r.decalage))",
                        "echelle=\(String(format: "%.2f", r.echelle))",
                        "pastille=\(arrowsView?.pastilleNecessaire ?? false)",
                        "cadre=\(panel.frame)", "curseur=\(NSEvent.mouseLocation)")
    }

    private func handleScroll(_ event: NSEvent) {
        // Pas de garde sur le mode ici : le monitor n'est simplement pas attaché quand le swipe
        // est désactivé (`majMoniteurScroll`). Une seule condition, un seul endroit.
        // La position du curseur est revérifiée ici plutôt que déduite d'un état latché par le
        // monitor `.mouseMoved` : celui-ci ne se remet pas à jour si le curseur reste immobile
        // pendant qu'une app d'encoche tierce déploie son panneau par-dessus.
        let phase = phaseGeste(event)
        let curseur = NSEvent.mouseLocation
        let dansLaZone = curseurDansLaZone()
        let decision = session.recoit(
            EvenementDefilement(
                phase: phase,
                inertie: event.momentumPhase != [],
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                instant: event.timestamp,
                dansLaZone: dansLaZone
            )
        )
        // Le journal note le verdict ET le garde qui l'a produit : un swipe qui ne déclenche rien
        // est autrement un silence, et un silence ne se débogue pas (cf. `TraceSwipe`).
        TraceSwipe.note(
            "scroll", "\(phase)", "verdict=\(decision)", "garde=\(session.raison.rawValue)",
            "dX=\(String(format: "%.1f", event.scrollingDeltaX))",
            "dY=\(String(format: "%.1f", event.scrollingDeltaY))",
            "accX=\(String(format: "%.1f", session.accumule.x))",
            "phaseNS=\(event.phase.rawValue)", "momentum=\(event.momentumPhase.rawValue)",
            "dansLaZone=\(dansLaZone)", "curseur=(\(Int(curseur.x)),\(Int(curseur.y)))",
            "gesteEnCours=\(session.gesteEnCours)", "t=\(String(format: "%.4f", event.timestamp))"
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

/// Flèches ‹ › de part et d'autre de ce qui couvre l'encoche, révélées progressivement à
/// l'approche : elles GLISSENT vers l'extérieur en même temps qu'elles apparaissent.
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

    /// De combien de points la flèche sort pendant la révélation. 0 = fondu seul.
    var retrait: CGFloat = 0

    /// Vrai seulement si la flèche se retrouve dessinée PAR-DESSUS la fenêtre d'une app tierce.
    /// Cf. `fondPastille` : c'est le seul cas où le contraste ne nous appartient plus.
    var pastilleNecessaire: Bool = false {
        didSet {
            guard pastilleNecessaire != oldValue else { return }
            appliqueHabillage()
        }
    }

    /// Le côté du chevron. Le calcul vit dans BouncerCore, où un test le voit (`tailleFleche`).
    var tailleFleche: CGFloat { BouncerCore.tailleFleche(hauteurBande: bounds.height) }

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
            button.wantsLayer = true
            button.target = self
            button.tag = forward ? 1 : 0
            button.action = #selector(arrowTapped(_:))
            button.alphaValue = 0
            addSubview(button)
        }
        appliqueHabillage()
        layoutArrows()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }

    override func layout() {
        super.layout()
        layoutArrows()
    }

    /// Fond de la pastille. MESURÉ le 2026-09-05 : la fenêtre de boringNotch fait 640 pt de large
    /// (975→1615 sur la machine de référence) alors que le boîtier caméra n'en fait que 166
    /// (1212→1378). Tant que les flèches se logeaient dans une marge fixe de 44 pt, elles étaient
    /// dessinées par-dessus une surface qui ne nous appartient pas et dont on ne sait rien : noir
    /// de l'île déployée, pochette d'album, visualiseur. Un glyphe monochrome y disparaît quelle
    /// que soit la couleur choisie — d'où cette pastille.
    ///
    /// Déplacer les flèches HORS de cette surface a été essayé, en les calant sur les bornes de la
    /// fenêtre : ça réglait le contraste et ça posait les chevrons au milieu des icônes de statut,
    /// à qui ils volaient le clic (QA du 2026-09-05, défaut N1). Le contraste ne vaut pas ça. Les
    /// flèches sont donc revenues contre le boîtier, et la pastille avec elles — mais seulement
    /// quand le recouvrement est réel, ce que `flechesPoseesSurUneAppTierce` mesure à chaque
    /// reconstruction. Un chevron invisible reste pire qu'un chevron entouré.
    private static let fondPastille = NSColor.black.withAlphaComponent(0.55).cgColor

    /// Sans pastille, le contraste repose sur la barre des menus — qui suit l'apparence système,
    /// donc `.labelColor` y est juste par construction. Le halo couvre le cas restant : une barre
    /// rendue translucide sur un fond d'écran clair en apparence sombre (ou l'inverse), où le
    /// glyphe seul frôlerait la limite. Il coûte une ombre de calque, pas un disque de 22 pt.
    private func appliqueHabillage() {
        for button in [leftButton, rightButton] {
            button.contentTintColor = pastilleNecessaire ? .white : .labelColor
            button.layer?.backgroundColor = pastilleNecessaire ? Self.fondPastille : nil
            button.layer?.shadowColor = pastilleNecessaire ? nil : NSColor.textBackgroundColor.cgColor
            button.layer?.shadowOpacity = pastilleNecessaire ? 0 : 0.7
            button.layer?.shadowRadius = 2.5
            button.layer?.shadowOffset = .zero
        }
        layoutArrows()
    }

    private func layoutArrows() {
        let cadres = cadresFleches(overlay: bounds.size, marge: margeLaterale)
        // Le décalage est SIGNÉ par côté : la flèche gauche sort vers la gauche, la droite vers la
        // droite. Un décalage commun les ferait glisser toutes les deux du même côté, ce qui se
        // lit comme un défaut d'alignement et pas comme un déploiement.
        leftButton.frame = cadres.gauche.offsetBy(dx: -revelation.decalage, dy: 0)
        rightButton.frame = cadres.droite.offsetBy(dx: revelation.decalage, dy: 0)
        for button in [leftButton, rightButton] {
            guard let calque = button.layer else { continue }
            calque.cornerRadius = cadres.gauche.width / 2
            // L'échelle se pose sur le calque et autour de son centre : redimensionner le `frame`
            // décalerait aussi la cible de clic, et une cible qui change de taille pendant qu'on
            // la vise est une cible qu'on rate.
            //
            // Centrer l'ancre ne suffit PAS à laisser le calque en place : AppKit garde sa
            // `position` sur l'origine du cadre, si bien que déplacer l'ancre déplace le dessin
            // d'une demi-taille vers le bas — et le bord bas du panel en écrêtait le reste. C'est
            // le défaut des « flèches à moitié coupées » ; `ancreAuCentre` (BouncerCore) recale la
            // position dans la foulée, et n'a aucun effet sur le cadre de la vue, donc aucun sur
            // la cible de clic.
            ancreAuCentre(calque, cadreVue: button.frame)
            calque.transform = CATransform3DMakeScale(revelation.echelle, revelation.echelle, 1)
        }
    }

    /// Le panel couvre une portion de barre des menus dès l'approche : sans ce passe-plat, il
    /// avalerait les clics sur les menus et les icônes de statut qui s'y trouvent. Seuls les deux
    /// boutons répondent, et seulement une fois franchement visibles — une flèche à 10 %
    /// d'opacité est une cible qu'on ne voit pas, donc qu'on ne vise pas volontairement.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard revelation.opacite >= 0.5 else { return nil }
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    @objc private func arrowTapped(_ sender: NSButton) {
        onArrowClicked?(sender.tag == 1)
    }

    /// Le fondu ET le déploiement, c'est cette valeur : elle suit la distance du curseur, donc la
    /// main. Pas d'animation de durée fixe — elle se battrait contre le mouvement au lieu de
    /// l'accompagner, et sur un aller-retour rapide au bord de la zone elle traînerait derrière le
    /// curseur. La courbe, elle, vit dans `revelationFleches` (BouncerCore), où elle se teste.
    var revelation = RevelationFleches(opacite: 0, decalage: 0, echelle: 1) {
        didSet {
            leftButton.alphaValue = revelation.opacite
            rightButton.alphaValue = revelation.opacite
            // Le repositionnement est fait DANS la même passe que l'opacité, sans animation
            // implicite : Core Animation en poserait une de 0,25 s sur `frame` et `transform`, et
            // elle traînerait derrière le curseur exactement comme celle qu'on refuse.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutArrows()
            CATransaction.commit()
        }
    }
}
