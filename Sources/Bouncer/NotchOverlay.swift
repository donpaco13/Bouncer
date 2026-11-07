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
// CE N'EST PAS LA MÊME ZONE QUE CELLE DES FLÈCHES. Les flèches restent collées au boîtier (calées
// sur la fenêtre d'encoche, elles tombaient sur les icônes de statut) ; le geste suit l'île en
// largeur, borné en hauteur sans quoi il avale les défilements horizontaux ordinaires. Les deux
// calculs vivent côte à côte dans BouncerCore (`zoneSurvol` / `zoneSwipe`).
//
// Géométrie dérivée de `zoneEncoche()` (source unique, cf. CLAUDE.md "zéro hardcoding
// d'encoche"), élargie de `margeLaterale` de chaque côté : le boîtier n'est pas affichable, une
// flèche dessinée dedans serait cachée par le matériel. Les flèches se logent dans ces marges.
//
// LES FLÈCHES SONT DES INDICATEURS PASSIFS, dans la rangée de la barre des menus, à hauteur de
// l'encoche. Le panel ignore la souris (`panelFleches`, BouncerCore) : il dessine par-dessus les
// titres de menus sans jamais leur prendre un clic. On bascule par swipe, raccourci ou menu.
//
// Le panel n'est à l'écran (`orderFrontRegardless()`) que pendant l'approche, et retiré
// (`orderOut(nil)`) dès que le curseur s'éloigne : resté en permanence, même transparent, il
// masquait le logo replié de Vibe Island (constaté en réel) ; on supprime le besoin.
//
// Le survol est détecté par un monitor GLOBAL (`.mouseMoved`) : le panel ignore la souris, il ne
// reçoit donc RIEN, et un monitor local ne verrait jamais l'entrée dans la zone. Le scroll est
// capté par un monitor GLOBAL aussi (`.scrollWheel`) : dès qu'une app d'encoche tierce déploie son
// panneau, sa fenêtre consomme le scroll avant nous. Le monitor global observe l'événement quel
// que soit qui le consomme ensuite — c'est pour ça que `handleScroll` et `updateHover` revérifient
// la position du curseur via `zoneSensible` plutôt que de faire confiance au frame du panel.
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
    /// Le boîtier caméra : le toucher est le geste qui déploie l'app d'encoche (cf.
    /// `encocheOccupee`). Mis en cache comme `zoneSensible`, pour la même raison.
    private var boitierCourant: CGRect?
    private var opaciteCourante: CGFloat = 0

    /// Les deux horloges des pistes temporelles (P1/P2). Repère `systemUptime` : monotone, donc
    /// insensible au changement d'heure système, contrairement à `Date()`.
    /// `instantEntree` vaut 0 tant que le curseur n'est pas dans la portée.
    private var instantEntree: TimeInterval = 0
    private var instantMouvement: TimeInterval = 0
    private var dernierePosition: CGPoint = .zero
    /// Ne tourne QUE si une des deux horloges est réglée ET que le curseur est dans la portée.
    /// Aux valeurs par défaut (les deux à zéro) il n'existe jamais : les pistes ne coûtent rien
    /// tant qu'on ne les essaie pas.
    private var tickerTemporel: Timer?
    /// L'app d'encoche est-elle déployée sur les flèches ? État tenu par `encocheOccupee`.
    private var appDeployee = false

    // `sideMargin` (44 pt) et `porteeApproche` (72 pt) étaient des constantes ici. La seconde
    // était la SEULE du projet restée réglée à l'œil, et les deux décident de la sensation du
    // geste : elles vivent désormais dans `Reglages`, avec ces mêmes valeurs en défaut.

    /// La session porte le détecteur ET sa durée de vie (cf. `SessionSwipe`) : c'est le
    /// remplacement du détecteur EN COURS DE GESTE qui produisait deux bascules pour un geste.
    private var session = SessionSwipe()

    /// Le cycle a-t-il au moins une cible ? Mis en cache et non redemandé à chaque événement :
    /// `cycleAUneCible` traverse `entreesMenu`, qui interroge LaunchServices pour chaque bundleID
    /// du catalogue, et `updateHover` tourne à chaque mouvement du curseur. Sans cible, les
    /// flèches annonceraient une bascule qui ne fera rien.
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
        tickerTemporel?.invalidate()
    }

    /// La fenêtre d'encoche à prendre en compte, ou `nil` si l'utilisateur a choisi de se caler
    /// sur le boîtier seul (ou qu'aucune app d'encoche n'est à l'écran).
    private func fenetreDeReference() -> CGRect? {
        reglages.ancrageZone == .fenetreEncoche ? windowManager.cadreFenetresEncoche : nil
    }

    /// La bande des flèches (cadre du panel, dans la rangée de la barre des menus) et le boîtier
    /// caméra, ou `nil` sans encoche.
    private func geometrie() -> (bande: CGRect, boitier: CGRect)? {
        guard let (encoche, _, _) = zoneEncoche() else { return nil }
        return (zoneSurvol(encoche: encoche, marge: reglages.margeLaterale), encoche)
    }

    /// (Re)positionne le panel sur la zone actuelle. Pas d'encoche détectée -> pas de
    /// panel, pas de crash (appelé aussi au changement de configuration d'écrans).
    @objc private func rebuild() {
        guard let (zone, boitier) = geometrie() else {
            zoneSensible = nil
            boitierCourant = nil
            teardownPanel()
            return
        }
        zoneSensible = zoneSwipe(bande: zone, fenetre: fenetreDeReference())
        boitierCourant = boitier
        if let panel {
            panel.setFrame(zone, display: true)
            arrowsView?.frame = NSRect(origin: .zero, size: zone.size)
            arrowsView?.margeLaterale = reglages.margeLaterale
        } else {
            buildPanel(zone: zone)
        }
        arrowsView?.retrait = reglages.retraitFleches
        arrowsView?.alignement = reglages.alignementFleches
        // Correctif de contraste, gardé : dans les marges du boîtier, une app d'encoche peut
        // dessiner sous les flèches (île, pochette), et c'est le recouvrement réel qui décide.
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
        let x = abscissesFleches(largeurOverlay: cadre.width, marge: reglages.margeLaterale,
                                 taille: taille, alignement: reglages.alignementFleches)
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
        tickerTemporel?.invalidate()
        tickerTemporel = nil
        panel?.orderOut(nil)
        panel = nil
        arrowsView = nil
        opaciteCourante = 0
        appDeployee = false
    }

    private func buildPanel(zone: CGRect) {
        let p = panelFleches(cadre: zone)
        let arrows = NotchArrowsView(frame: NSRect(origin: .zero, size: zone.size), margeLaterale: reglages.margeLaterale)
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
        guard let panel, let boitier = boitierCourant, zoneSensible != nil else { return }
        // AVANT la garde d'opacité : en mode « swipe seul » l'opacité vaut zéro en permanence, et
        // une garde placée plus haut empêcherait le monitor d'être jamais attaché.
        majMoniteurScroll()

        // Le curseur qui entre dans la zone est le signal le plus sûr que l'utilisateur va agir,
        // et c'est le seul que le système ne poste nulle part : une app d'encoche qui détruit sa
        // fenêtre sans quitter son process n'émet aucune notification, seul le sondage la voit.
        // Distingue « le curseur passe » de « le curseur s'arrête » : une simple traversée vers la
        // barre des menus ou les onglets ne réveille pas le sondage.
        let curseur = NSEvent.mouseLocation
        let maintenant = ProcessInfo.processInfo.systemUptime
        // `updateHover` est appelée par le monitor souris ET par le ticker temporel : mesurer
        // l'immobilité à la POSITION plutôt qu'à l'origine de l'appel évite de traiter un tour de
        // ticker comme un mouvement.
        if curseur != dernierePosition {
            dernierePosition = curseur
            instantMouvement = maintenant
        }

        let dansLaZone = curseurDansLaZone()
        if dansLaZone != curseurEtaitDansLaZone {
            windowManager.curseurDansZone(dansLaZone)
            curseurEtaitDansLaZone = dansLaZone
        }

        appDeployee = encocheOccupee(
            dejaOccupee: appDeployee, curseur: curseur, boitier: boitier,
            fenetre: windowManager.cadreFenetresEncoche, cadreFleches: panel.frame
        )

        // Trois raisons de ne rien montrer, et c'est la même : la flèche n'aurait rien à dire.
        // Le mode « swipe seul », choisi ; un cycle sans aucune cible ; et l'app d'encoche
        // déployée par-dessus (`encocheOccupee`, BouncerCore). La progression se mesure à la
        // BANDE des flèches, pas à la zone de swipe, qui descend jusqu'en bas de l'île.
        let geometrique = (reglages.modeActivation.flechesActives && cycleAUneCible && !appDeployee)
            ? opaciteFleches(curseur: curseur, zone: panel.frame, portee: reglages.porteeApproche)
            : 0
        // L'horloge d'entrée démarre au franchissement de la portée et se remet à zéro à la
        // sortie : c'est ce qui fait qu'un aller-retour ne CUMULE pas du temps de présence.
        if geometrique <= 0 {
            instantEntree = 0
        } else if instantEntree == 0 {
            instantEntree = maintenant
        }
        // Aux valeurs par défaut (les deux horloges à zéro), `facteurTemporel` rend 1 : la
        // progression est exactement celle d'avant.
        let progression = geometrique * facteurTemporel(
            depuisEntree: instantEntree > 0 ? maintenant - instantEntree : 0,
            depuisMouvement: maintenant - instantMouvement,
            delai: reglages.delaiRevelation,
            inactivite: reglages.inactiviteFleches
        )
        // AVANT la garde : un curseur immobile n'émet plus rien, donc sans ce ticker le délai ne
        // s'écoulerait jamais et l'effacement sur inactivité n'arriverait jamais.
        majTickerTemporel(dansLaPortee: geometrique > 0)

        guard progression != opaciteCourante else { return }
        let etaitVisible = opaciteCourante > 0
        opaciteCourante = progression

        if progression > 0 {
            if !etaitVisible { panel.orderFrontRegardless() }
        } else {
            panel.orderOut(nil)
        }
        let r = revelationFleches(progression: progression, retrait: reglages.retraitFleches,
                                  courbe: reglages.courbeRevelation)
        arrowsView?.revelation = r
        TraceSwipe.note("survol", "progression=\(String(format: "%.2f", progression))",
                        "opacite=\(String(format: "%.2f", r.opacite))",
                        "decalage=\(String(format: "%.1f", r.decalage))",
                        "echelle=\(String(format: "%.2f", r.echelle))",
                        "pastille=\(arrowsView?.pastilleNecessaire ?? false)",
                        "cadre=\(panel.frame)", "curseur=\(NSEvent.mouseLocation)")
    }

    /// Attache ou détache le ticker des pistes temporelles, exactement sous la condition où un
    /// tour pourrait changer quelque chose : une horloge réglée, et le curseur dans la portée.
    ///
    /// Même principe que `majMoniteurScroll` : on change QUAND on écoute, jamais quoi. Hors
    /// portée il n'y a rien à faire descendre ni à faire monter, et aux valeurs par défaut le
    /// ticker n'est jamais créé du tout.
    private func majTickerTemporel(dansLaPortee: Bool) {
        let voulu = dansLaPortee && reglages.revelationTemporelleActive
        if voulu, tickerTemporel == nil {
            // 1/30 s : la transition dure 0,18 s, donc cinq pas au minimum — assez pour que
            // l'effacement se lise comme un fondu et pas comme une coupure.
            tickerTemporel = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateHover() }
            }
        } else if !voulu, let t = tickerTemporel {
            t.invalidate()
            tickerTemporel = nil
        }
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
        // sens, et `cycle` reboucle, donc pas de cul-de-sac. Un sens de geste se retient mal
        // (retour de test réel du 2026-09-05).
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
    // Des `NSImageView` et pas des boutons : les flèches sont des indicateurs passifs, le panel
    // ignore la souris (`panelFleches`).
    private let leftArrow = NSImageView()
    private let rightArrow = NSImageView()
    /// Largeur de la bande visible à chaque extrémité : les flèches s'y centrent, jamais au milieu
    /// où le boîtier caméra les cacherait. Variable, parce qu'elle est réglable et que le panel
    /// est construit une seule fois puis repositionné.
    var margeLaterale: CGFloat {
        didSet { layoutArrows() }
    }

    /// De combien de points la flèche sort pendant la révélation. 0 = fondu seul.
    var retrait: CGFloat = 0

    /// Où le chevron se pose DANS sa marge : 0 = collé au boîtier caméra, 1 = au bord extérieur.
    /// Cf. `abscissesFleches` (BouncerCore) — piste P3, réglable, défaut inchangé.
    var alignement: CGFloat = alignementFlechesDefaut {
        didSet {
            guard alignement != oldValue else { return }
            layoutArrows()
        }
    }

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

        for (fleche, symbol) in [(leftArrow, "chevron.left"), (rightArrow, "chevron.right")] {
            fleche.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            fleche.imageScaling = .scaleProportionallyDown
            fleche.wantsLayer = true
            fleche.alphaValue = 0
            addSubview(fleche)
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
    /// quand le boîtier n'en fait que 166 ; dans les marges, l'app peut dessiner (île noire,
    /// pochette d'album, visualiseur). Un glyphe monochrome y disparaît quelle que soit sa couleur.
    /// `flechesPoseesSurUneAppTierce` mesure ce recouvrement à chaque reconstruction.
    private static let fondPastille = NSColor.black.withAlphaComponent(0.55).cgColor

    /// Sans pastille, le contraste repose sur la barre des menus — qui suit l'apparence système,
    /// donc `.labelColor` y est juste par construction. Le halo couvre le cas restant : une barre
    /// rendue translucide sur un fond d'écran clair en apparence sombre (ou l'inverse), où le
    /// glyphe seul frôlerait la limite. Il coûte une ombre de calque, pas un disque de 22 pt.
    private func appliqueHabillage() {
        for fleche in [leftArrow, rightArrow] {
            fleche.contentTintColor = pastilleNecessaire ? .white : .labelColor
            fleche.layer?.backgroundColor = pastilleNecessaire ? Self.fondPastille : nil
            fleche.layer?.shadowColor = pastilleNecessaire ? nil : NSColor.textBackgroundColor.cgColor
            fleche.layer?.shadowOpacity = pastilleNecessaire ? 0 : 0.7
            fleche.layer?.shadowRadius = 2.5
            fleche.layer?.shadowOffset = .zero
        }
        layoutArrows()
    }

    private func layoutArrows() {
        let cadres = cadresFleches(overlay: bounds.size, marge: margeLaterale, alignement: alignement)
        // Le décalage est SIGNÉ par côté : la flèche gauche sort vers la gauche, la droite vers la
        // droite. Un décalage commun les ferait glisser toutes les deux du même côté, ce qui se
        // lit comme un défaut d'alignement et pas comme un déploiement.
        leftArrow.frame = cadres.gauche.offsetBy(dx: -revelation.decalage, dy: 0)
        rightArrow.frame = cadres.droite.offsetBy(dx: revelation.decalage, dy: 0)
        for fleche in [leftArrow, rightArrow] {
            guard let calque = fleche.layer else { continue }
            calque.cornerRadius = cadres.gauche.width / 2
            // L'échelle se pose sur le calque, autour de son centre. Centrer l'ancre seule
            // décalerait le dessin d'une demi-taille (flèches « à moitié coupées ») :
            // `ancreAuCentre` (BouncerCore) recale la position dans la foulée.
            ancreAuCentre(calque, cadreVue: fleche.frame)
            calque.transform = CATransform3DMakeScale(revelation.echelle, revelation.echelle, 1)
        }
    }

    /// Le fondu ET le déploiement, c'est cette valeur : elle suit la distance du curseur, donc la
    /// main. Pas d'animation de durée fixe — elle se battrait contre le mouvement au lieu de
    /// l'accompagner, et sur un aller-retour rapide au bord de la zone elle traînerait derrière le
    /// curseur. La courbe, elle, vit dans `revelationFleches` (BouncerCore), où elle se teste.
    var revelation = RevelationFleches(opacite: 0, decalage: 0, echelle: 1) {
        didSet {
            leftArrow.alphaValue = revelation.opacite
            rightArrow.alphaValue = revelation.opacite
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
