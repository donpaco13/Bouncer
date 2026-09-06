//
// WindowManager.swift — Milestone 1 : détection et régie des apps d'encoche.
//
// Reprend telle quelle la logique validée au Milestone 0 (Spike.swift, SPIKE_RESULTS.md) :
//   - géométrie de l'encoche via NSScreen.screens (pas NSScreen.main, cf. écran secondaire),
//   - conversion de repère CGWindowList (haut-gauche) -> AppKit (bas-gauche) via screens[0],
//   - seule stratégie de masquage qui marche parfois : kAXHiddenAttribute au niveau application,
//   - seul juge de vérité pour le succès d'un hide/show : recomptage CGWindowListCopyWindowInfo
//     sur le pid ciblé — jamais le code retour AX, jamais la relecture d'attribut (les deux mentent
//     sur boringNotch, cf. SPIKE_RESULTS.md §Étape D et §Q1).
//
// Une app non régissable est détectée, testée une fois à sa découverte, puis marquée "non
// supportée" et exclue du cycle de switch — jamais retestée en boucle, jamais laissée masquée
// après le test.

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

public enum SupportStatus: String {
    case testing = "Test en cours…"
    case supported = "Régissable"
    case unsupported = "Non supportée"
}

/// L'identité d'une app est son bundleID, jamais son pid : une app qu'on a quittée n'a plus de
/// pid mais doit rester listée — c'est elle qu'on relancera à la bascule suivante.
public struct NotchAppInfo: Identifiable, Equatable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public var support: SupportStatus
    /// nil quand l'app n'est pas lancée. Une app tuée reste listée : c'est elle qu'on relancera.
    public var pid: pid_t?
    public var isHiddenByUs: Bool
    public var estLancee: Bool { pid != nil }
}

/// Processus systèmes à ignorer dans le scan de la zone d'encoche, identifiés par bundleID —
/// jamais par nom d'affichage localisé (kCGWindowOwnerName suit la langue système : "Centre de
/// notifications" en français, "Notification Center" en anglais).
///
/// `UserNotificationCenter` est le démon d'alertes modales, distinct de `notificationcenterui` qui
/// affiche les bannières : il figurait bel et bien dans le catalogue de la machine de référence, et
/// s'il y est entré par la fuite inter-écrans corrigée dans `estFenetreEncoche`, il n'a de toute
/// façon rien à faire dans un cycle d'apps d'encoche.
private let systemBundleIDs: Set<String> = [
    "com.apple.notificationcenterui", "com.apple.UserNotificationCenter",
    "com.apple.controlcenter", "com.apple.dock",
    "com.apple.systemuiserver", "com.apple.loginwindow", "com.apple.PowerChime",
    "com.apple.Spotlight", "com.apple.WindowManager",
]

// Il n'y a plus de repli par nom d'affichage. Il ne servait qu'aux process sans
// NSRunningApplication — donc sans bundleID, aujourd'hui le seul Window Server — et ces process-là
// sont maintenant écartés par une règle plus large dans `scanNotchApps` : sans bundleID, une app
// n'a pas d'identité stable, on ne peut ni la relancer ni mémoriser son verdict. Window Server
// reste donc exclu, par la règle générale plutôt que par son nom d'affichage localisé.

/// `@MainActor` : la classe publie vers SwiftUI et pilote des API AppKit, et le protocole
/// `ControleurApps` qu'elle utilise porte le même contrat. L'isolation était déjà vraie en
/// pratique — elle est maintenant vérifiée par le compilateur.
@MainActor
public final class WindowManager: ObservableObject {
    @Published public private(set) var apps: [NotchAppInfo] = []
    @Published public private(set) var accessibilityTrusted: Bool = false
    @Published public private(set) var lastNotchZoneDescription: String = "—"
    /// Le cadre de ce qui COUVRE réellement l'encoche : réunion des fenêtres d'apps d'encoche
    /// détectées, en repère AppKit. `nil` quand il n'y en a aucune.
    ///
    /// C'est ce qui permet à l'overlay d'écouter là où l'utilisateur vise, plutôt qu'une bande
    /// fixe de 254 pt autour d'un boîtier de 166 (cf. `zoneSurvol` / `zoneSwipe`). MESURÉ le
    /// 2026-09-05 : boringNotch pose un conteneur de 640×210 pt, Vibe Island de 740×520 — et ces
    /// cadres NE BOUGENT PAS quand l'île se déploie, ce sont des conteneurs transparents de
    /// taille fixe. On mesure donc l'emprise maximale de l'app, ce qui est exactement la garantie
    /// dont les flèches ont besoin pour ne jamais être dessinées par-dessus.
    @Published public private(set) var cadreFenetresEncoche: CGRect?

    /// bundleID de l'app dont la bascule est en cours, `nil` si aucune. Publié parce que le menu
    /// doit le montrer : la voie par cycle de vie prend environ une seconde, et sans retour visuel
    /// l'utilisateur clique une seconde fois.
    ///
    /// Il sert aussi de verrou : tant qu'il n'est pas `nil`, toute nouvelle demande de bascule
    /// est ignorée. Deux bascules concurrentes se marcheraient dessus — la seconde éteindrait
    /// l'app que la première vient tout juste d'allumer.
    @Published public private(set) var bundleIDEnCoursDeBascule: String?

    /// Ce que la dernière bascule a raté, dit en clair, `nil` si elle a abouti. Un échec ne change
    /// rien à l'écran — l'app précédente reste en place, c'est la garantie de la machine à états —
    /// donc sans ce message l'utilisateur ne verrait qu'un geste sans effet.
    @Published public private(set) var echecBascule: String?

    /// Bouncer s'écarte elle-même du scan par bundleID, jamais par pid.
    ///
    /// Son overlay EST une fenêtre d'encoche au sens du filtre — relevé le 5 septembre 2026 :
    /// `layer 35, X:1148→1442, sommet à cadre.maxY`, les trois conditions passent. Rien de
    /// géométrique ne peut donc l'écarter, seule son identité le peut. L'ancien `pid == ownPid`
    /// n'écartait que l'instance COURANTE : une seconde copie lancée depuis un autre chemin, ou
    /// l'ancienne version encore ouverte pendant une mise à jour, avait un autre pid, franchissait
    /// le filtre et entrait au catalogue — c'est ainsi que `io.github.donpaco13.bouncer` s'est
    /// retrouvé dans le cycle de bascule de François, qui l'emmenait sur Bouncer elle-même.
    /// Le pid est le mauvais axe dès qu'une app peut exister en plusieurs exemplaires.
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var timer: Timer?
    private var observateurQuit: (any NSObjectProtocol)?

    /// Nombre de tours de sondage consécutifs qui n'ont RIEN vu changer. C'est la seule mesure
    /// qui décide de la cadence : tant qu'elle monte, le timer s'espace ; elle retombe à zéro
    /// dès qu'un scan trouve autre chose ou qu'un réveil arrive.
    private var toursImmobiles = 0

    /// Empreinte du dernier scan. Comparer deux tours, c'est comparer ces deux chaînes.
    private var derniereEmpreinte = ""

    /// La période réellement posée sur le timer. Un `Timer` ne change pas de période : sans ce
    /// souvenir, `replanifierTimer` en reposerait un neuf à chaque tour pour rien.
    private var periodePosee: TimeInterval = 0

    /// Les notifications qui remettent la cadence au plus rapide.
    private var observateursReveil: [any NSObjectProtocol] = []

    /// Plafond du ralentissement au repos. Un changement qu'aucune notification ne signale — une
    /// app d'encoche qui détruit sa fenêtre sans quitter son process — n'est vu que par le
    /// sondage : au-delà de cette période, le menu mettrait trop longtemps à se corriger.
    private nonisolated static let periodeMaxAuRepos: TimeInterval = 30

    /// Nombre de tours identiques tolérés avant de commencer à ralentir. Trois tours à la période
    /// par défaut font six secondes de cadence pleine après le moindre mouvement : l'utilisateur
    /// qui vient d'agir ne tombe jamais sur une app molle.
    private nonisolated static let toursAvantRalentissement = 3

    /// Toutes les actions sur les apps tierces passent par là. Injectable : c'est ce qui rendra
    /// la bascule testable sans lancer ni tuer de vraies apps.
    private let controleur: ControleurApps

    /// Verdict de régissabilité par bundleID, pour la durée de vie de Bouncer — indépendant de la
    /// présence de l'app dans `apps`. Sans ce cache, une app qui sort de `apps` (fenêtre absente
    /// une fraction de seconde) puis y revient repasserait par `testSupport`, qui masque/réaffiche
    /// réellement la fenêtre : l'app clignoterait à chaque redécouverte.
    ///
    /// La clé est le bundleID et non le pid, ce qui règle deux choses d'un coup : le système
    /// recycle un pid — le verdict d'une app morte pouvait donc être attribué à un process sans
    /// rapport — alors qu'un bundleID n'est jamais recyclé ; et le verdict survit à une app qu'on
    /// quitte puis relance, qui reprend son verdict sans repasser par le test destructif.
    private var supportVerdictCache: [String: SupportStatus] = [:]

    /// Les apps de notch installées, lancées ou non. Alimenté par la découverte : toute app vue
    /// une fois dans le notch y est mémorisée pour de bon. La construction de `apps` à partir de
    /// ce catalogue (donc l'apparition des apps arrêtées dans la liste) vient avec la bascule.
    private let catalogue: CatalogueApps

    /// La machine à états de la bascule, montée sur le même contrôleur que le reste. Une seule
    /// instance, un seul chemin : le swipe, les flèches et le menu y aboutissent tous. Deux
    /// chemins qui font « la même chose » finiraient par diverger.
    private let bascule: Bascule

    /// Les préférences. Deux d'entre elles arrivent jusqu'ici : la période du timer et la liste
    /// des apps exclues du cycle. Passées par référence depuis `BouncerApp`, la même instance que
    /// celle de la fenêtre de réglages et de l'overlay — sinon un changement ne traverserait pas.
    public let reglages: Reglages
    private var abonnementReglages: AnyCancellable?

    /// D'où vient la géométrie de l'encoche. Injectable pour exactement la même raison que
    /// `controleur` : vérifier qu'un changement d'écrans est bien répercuté ne doit pas demander
    /// de débrancher un moniteur. Rien n'est mis en cache derrière — la valeur par défaut
    /// `zoneEncoche()` relit `NSScreen.screens` à chaque appel — mais l'appeler à CHAQUE sondage
    /// est ce qui rend la géométrie périmée impossible : sur la machine de référence le MacBook
    /// n'est pas l'écran principal et la bande d'encoche vit en y négatifs, le multi-écrans y est
    /// le cas nominal, pas un cas limite.
    private let geometrie: @MainActor () -> (rect: CGRect, ecran: String, cadre: CGRect)?

    /// Faux pour le self-test CLI : aucun timer n'est posé, y compris par un réveil. Sans ce
    /// drapeau, une notification système reposait un timer que `startTimer: false` avait
    /// justement refusé.
    private let sondageActif: Bool

    /// `startTimer: false` pour le self-test CLI (un seul sondage synchrone, pas de boucle).
    public init(
        startTimer: Bool = true,
        catalogue: CatalogueApps = CatalogueApps(),
        controleur: ControleurApps = ControleurAppsSysteme(),
        reglages: Reglages = Reglages(),
        geometrie: @escaping @MainActor () -> (rect: CGRect, ecran: String, cadre: CGRect)? = zoneEncoche,
        demanderAccessibilite: Bool = true
    ) {
        self.catalogue = catalogue
        self.controleur = controleur
        self.reglages = reglages
        self.geometrie = geometrie
        sondageActif = startTimer
        bascule = Bascule(controleur: controleur)
        accessibilityTrusted = AXIsProcessTrusted()
        // `demanderAccessibilite: false` pour les tests : la popup système est modale et bloquerait
        // `swift test` sur la machine de qui la lance. Elle reste vraie partout ailleurs, y compris
        // dans le self-test CLI — c'est même son intérêt, l'autorisation se donne par binaire.
        if !accessibilityTrusted, demanderAccessibilite {
            // Popup système une seule fois, ici, à froid — jamais dans la boucle de refresh.
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as NSDictionary
            )
        }
        sonder()
        restaurerAppsMasquees()
        // Avant le garde, et c'est le correctif : brancher un écran, en débrancher un, réveiller
        // le Mac ou changer d'écran principal déplace l'encoche, donc TOUT ce que le sondage
        // regarde. Ces observateurs ne dépendent pas du timer — ils sont la seule chose qui dise
        // à Bouncer que sa géométrie vient de changer, et un `startTimer: false` ne doit pas les
        // emporter avec la boucle.
        observerReveils()
        guard startTimer else { return }
        replanifierTimer()
        // La contrepartie de la restauration au démarrage : ranger avant de partir, pour ne pas
        // laisser l'utilisateur sans encoche entre deux lancements de Bouncer.
        //
        // `queue: nil` et pas `.main` : une queue non nulle fait passer le bloc par
        // `addOperation`, donc au tour de run loop SUIVANT — qui n'arrive jamais, l'app est en
        // train de mourir. Sans queue, le bloc s'exécute de façon synchrone sur le thread qui
        // poste, le thread principal pour cette notification-là, ce qui rend `assumeIsolated`
        // exact et le rangement effectif.
        observateurQuit = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restaurerAppsMasquees() }
        }
        // Changer la période dans les réglages doit valoir tout de suite : sans ça, il faudrait
        // relancer l'app pour voir l'effet du réglage qu'on vient de bouger.
        abonnementReglages = reglages.changementsIntervalle
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] intervalle in
                MainActor.assumeIsolated {
                    // Bouger le réglage EST une interaction : on repart à cadence pleine, sinon
                    // l'utilisateur qui passe de 30 s à 1 s attendrait encore trente secondes.
                    self?.toursImmobiles = 0
                    self?.replanifierTimer(base: intervalle)
                }
            }
    }

    /// Période à poser, compte tenu du repos observé : la période réglée tant que quelque chose
    /// bouge, doublée à chaque tour immobile au-delà du seuil, plafonnée à `periodeMaxAuRepos`.
    ///
    /// MESURÉ (docs/PERFORMANCE.md, rejoué le 5 septembre 2026 sur la machine de référence) : un
    /// tour de scan coûte 2,30 ms. À 2 s fixes, c'est 43 200 tours et 99 s de CPU par tranche de
    /// 24 h sur une machine que personne ne touche.
    ///
    /// `base` n'est passée que par l'abonnement aux réglages : `@Published` publie AVANT que la
    /// valeur soit écrite, donc relire `reglages` depuis son propre sink rendrait l'ANCIENNE
    /// période — c'est déjà la raison pour laquelle ce paramètre existait.
    ///
    /// Sans droits d'Accessibilité, on ne ralentit jamais. Le passage refusé -> accordé se fait
    /// dans les Réglages Système, aucune notification ne nous le dit, et c'est ce timer-là qui
    /// fait avancer l'accueil tout seul sous les yeux de l'utilisateur.
    private func periodeVoulue(base: TimeInterval? = nil) -> TimeInterval {
        Self.periodeDeRepos(
            base: base ?? reglages.intervalleRafraichissement,
            toursImmobiles: toursImmobiles,
            accessibiliteAccordee: accessibilityTrusted
        )
    }

    /// L'échelle elle-même, isolée de tout état pour être vérifiable (cf. `CadenceTests`).
    public nonisolated static func periodeDeRepos(
        base: TimeInterval, toursImmobiles: Int, accessibiliteAccordee: Bool
    ) -> TimeInterval {
        guard accessibiliteAccordee else { return base }
        let crans = max(0, toursImmobiles - toursAvantRalentissement)
        return min(base * pow(2, Double(min(crans, 8))), periodeMaxAuRepos)
    }

    /// (Re)pose le timer de resondage. Un `Timer` ne change pas de période : il faut l'invalider
    /// et en reposer un. Appelé à chaque tour, il ne fait donc rien tant que la cadence voulue
    /// n'a pas bougé.
    private func replanifierTimer(base: TimeInterval? = nil) {
        guard sondageActif else { return }
        let periode = periodeVoulue(base: base)
        guard periode != periodePosee || timer == nil else { return }
        periodePosee = periode
        timer?.invalidate()
        let nouveau = Timer.scheduledTimer(withTimeInterval: periode, repeats: true) { [weak self] _ in
            // Le timer est planifié sur la run loop principale : son callback s'exécute donc
            // déjà sur le main actor, `assumeIsolated` ne fait que le dire au compilateur.
            MainActor.assumeIsolated {
                self?.refreshTrustState()
                self?.replanifierTimer()
            }
        }
        // Laisser macOS grouper notre réveil avec ceux des autres process. Un timer sans
        // tolérance oblige le noyau à sortir le CPU de son état de repos rien que pour nous ;
        // 20 % de marge sur une période de repos n'est observable par personne.
        nouveau.tolerance = periode * 0.2
        timer = nouveau
    }

    /// Remet la cadence au plus rapide et resonde tout de suite.
    ///
    /// Les notifications système ne REMPLACENT pas le sondage, et c'est le point qui a fait
    /// rejeter la première version de ce correctif : `NSWorkspace.didLaunchApplication` dit qu'un
    /// process a démarré, jamais que sa fenêtre d'encoche est à l'écran — or c'est exactement
    /// l'écart que `scanNotchApps` mesure, et le cas NORMAL (la fenêtre arrive après le
    /// lancement). Une notification est donc un RÉVEIL : elle dit qu'il vaut la peine de resonder
    /// vite, et c'est le sondage qui constate.
    public func reveiller() {
        toursImmobiles = 0
        replanifierTimer()
        sonder()
    }

    /// Le « Rafraîchir » du menu : l'utilisateur redemande un état propre, et c'est la SEULE porte
    /// qui efface le triangle d'alerte.
    ///
    /// Elle ne peut pas être la boucle de sondage. `sonder()` passe toutes les deux secondes :
    /// un message d'échec qu'il effacerait disparaîtrait avant d'avoir été lu, ce qui est pire
    /// que le triangle figé qu'on corrige ici. Ni un réveil système (une app tierce qui démarre
    /// n'a rien à dire de la bascule qui vient de rater) ne doit l'effacer. Restent deux portes,
    /// toutes deux volontaires : celle-ci, et la bascule suivante.
    public func refresh() {
        echecBascule = nil
        reveiller()
    }

    /// Ce qui vaut la peine de resonder vite : une app apparaît ou disparaît, l'utilisateur change
    /// d'espace ou d'écran. S'abonne au même endroit que le timer — le self-test CLI ne veut ni
    /// l'un ni l'autre.
    private func observerReveils() {
        let reveil: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.reveiller() }
        }
        let atelier = NSWorkspace.shared.notificationCenter
        for nom in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            observateursReveil.append(
                atelier.addObserver(forName: nom, object: nil, queue: .main, using: reveil))
        }
        // Brancher un écran, en débrancher un, réveiller le Mac, changer l'écran principal : la
        // géométrie de l'encoche change, donc l'ENDROIT même que le scan doit regarder. C'est la
        // seule notification qui le dise ; sans elle le sondage continue de raisonner sur une
        // encoche qui n'est plus là.
        //
        // `queue: nil` et pas `.main`, pour la raison exposée sur `observateurQuit` : une queue
        // fait passer le bloc par `addOperation`, donc au tour de run loop SUIVANT. AppKit poste
        // cette notification sur le thread principal — `assumeIsolated` est donc exact — et sans
        // queue la géométrie est relue dans le tour même où l'écran a changé, au lieu d'un tour
        // de retard pendant lequel la bascule sonderait une encoche périmée.
        observateursReveil.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: nil, using: reveil))
    }

    /// Range le tour qui vient de finir : identique au précédent, ou pas.
    ///
    /// La trace n'est pas décorative : le gain de ce correctif se compte en TOURS par 24 h, et
    /// cette ligne est le seul endroit qui les compte pour de vrai. Une session de mesure
    /// s'ouvre comme celle du swipe (cf. `TraceSwipe`), et `awk` fait le reste.
    private func noterEmpreinte(_ empreinte: String) {
        TraceSwipe.note("sondage", "immobiles=\(toursImmobiles)",
                        "periode=\(String(format: "%.0f", periodePosee))",
                        "change=\(empreinte != derniereEmpreinte)")
        guard empreinte == derniereEmpreinte else {
            derniereEmpreinte = empreinte
            toursImmobiles = 0
            return
        }
        toursImmobiles += 1
    }

    /// Ouvre le volet Accessibilité des Réglages Système, pour que l'utilisateur y aille
    /// quand il veut plutôt que de subir la popup système.
    public func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Relit le trust sans jamais prompter (`AXIsProcessTrusted()`, pas la variante `WithOptions`).
    /// Au passage false -> true, les verdicts "Non supportée" obtenus sans droits AX sont faux :
    /// on les jette et on relance le test de régissabilité sur toutes les apps détectées.
    private func refreshTrustState() {
        let nowTrusted = AXIsProcessTrusted()
        let justGranted = nowTrusted && !accessibilityTrusted
        let justRevoked = !nowTrusted && accessibilityTrusted
        accessibilityTrusted = nowTrusted
        // Le droit qui bascule change tout ce que le sondage peut voir. Sans cette remise à zéro,
        // les tours immobiles accumulés PENDANT le refus (où l'on ne ralentit jamais) feraient
        // sauter la cadence à son plafond à la seconde même où l'utilisateur accorde l'accès —
        // c'est-à-dire au seul moment où il regarde l'app se débloquer.
        if justGranted || justRevoked { toursImmobiles = 0 }

        guard justGranted else {
            // Le passage true -> false ne changeait RIEN d'observable : le menu affichait déjà sa
            // ligne « Autoriser… », mais l'icône de la barre restait au repos et l'utilisateur qui
            // ne l'ouvrait pas voyait seulement ses gestes cesser de faire effet. Un échec muet
            // est le seul qu'on ne peut pas diagnostiquer — on le nomme.
            if justRevoked { signalerRevocation() }
            sonder()
            return
        }

        // ponytail: AXIsProcessTrusted() bascule à true avant que le serveur Accessibility
        // n'ait fini de propager côté API AX (constaté empiriquement : jusqu'à ~1s de
        // décalage) — un retest synchrone à l'instant du flip peut donc figer un faux "Non
        // supportée". On jette les verdicts et on laisse une seconde de marge avant de
        // retester. Si le décalage réel dépasse cette marge, prévoir un retry supplémentaire.
        // Le droit est revenu : le message de révocation ne décrit plus rien.
        echecBascule = nil
        apps.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sonder()
        }
    }

    /// Dit ce que la révocation vient de coûter, et nomme l'app coincée s'il y en a une. Passe
    /// par `echecBascule` et pas par une nouvelle propriété : c'est déjà le canal des échecs, et
    /// c'est lui qui fait passer l'icône de la barre en triangle d'alerte.
    private func signalerRevocation() {
        let coincees = apps.filter(\.isHiddenByUs).map(\.name)
        let sort = coincees.isEmpty
            ? "Les bascules quitteront les apps au lieu de les masquer."
            : "\(coincees.joined(separator: ", ")) \(coincees.count > 1 ? "sont masquées" : "est masquée") : une bascule les relancera pour les ramener."
        echecBascule = "L'accès à l'Accessibilité a été retiré à Bouncer. \(sort)"
    }

    /// Lève le masquage sur toutes les apps d'encoche connues qui tournent.
    ///
    /// `kAXHidden` survit à notre process. Une app que Bouncer a masquée puis oubliée — parce
    /// qu'il a été quitté, forcé à quitter, mis à jour ou qu'il a planté — reste invisible, et
    /// comme une app d'encoche n'a ni icône du Dock ni entrée Cmd-Tab, l'utilisateur n'a AUCUN
    /// moyen de la ramener : il la croit perdue. Ce filet tourne donc aux deux bouts de la vie de
    /// Bouncer, au démarrage (ce qu'une session morte a laissé derrière elle) et à la fermeture
    /// propre (ce que celle-ci a masqué).
    ///
    /// On balaye le catalogue et pas `apps` : une app masquée n'a par construction plus de
    /// fenêtre dans l'encoche, donc le scan ne la voit pas — au démarrage elle n'est nulle part
    /// ailleurs. L'appel est sans effet sur une app déjà visible.
    ///
    /// Le garde-fou sur le trust n'est pas une optimisation : toucher l'API AX sans droits met la
    /// connexion Accessibility de ce process hors service pour le reste de sa vie (cf. le
    /// commentaire de `refresh`).
    private func restaurerAppsMasquees() {
        guard accessibilityTrusted else { return }
        for installee in catalogue.installees() {
            guard let pid = controleur.pid(pour: installee.bundleID) else { continue }
            controleur.reafficherSansAttendre(pid: pid)
        }
    }

    // MARK: - Géométrie de l'encoche (portée depuis Spike.swift)

    /// Zone d'encoche en coordonnées AppKit globales (repère utilisé par `NSPanel.setFrame` et
    /// `NSEvent.mouseLocation`) — `public`, pour que `NotchOverlayController` (target exécutable)
    /// positionne son panel sans redériver la géométrie (règle CLAUDE.md : zéro hardcoding).
    /// Le calcul vit dans `zoneEncoche()` (ControleurApps.swift), pour que le recomptage par pid
    /// mesure exactement la même zone que le scan de découverte. Ne reste ici que la description
    /// publiée vers l'UI.
    public func notchZone() -> CGRect? {
        guard let (rect, ecran, _) = geometrie() else {
            publier(description: "Aucune encoche détectée sur cette machine.")
            return nil
        }
        publier(description: "\(ecran) — \(rect)")
        return rect
    }

    /// `@Published` ne déduplique pas : réassigner la même chaîne à chaque tour de timer réveille
    /// SwiftUI toutes les deux secondes pour rien (docs/PERFORMANCE.md §Priorité 3). La géométrie
    /// de l'encoche, elle, ne change qu'au branchement d'un écran.
    private func publier(description: String) {
        guard lastNotchZoneDescription != description else { return }
        lastNotchZoneDescription = description
    }

    /// Même précaution que `publier` : ce cadre est relu à chaque tour de timer et ne change qu'au
    /// lancement ou à l'arrêt d'une app d'encoche. Le réassigner à l'identique ferait reconstruire
    /// l'overlay toutes les deux secondes.
    private func publierCadre(_ cadre: CGRect?) {
        let normalise = (cadre?.isNull == true || cadre?.isEmpty == true) ? nil : cadre
        guard cadreFenetresEncoche != normalise else { return }
        cadreFenetresEncoche = normalise
    }

    // MARK: - Scan (portée depuis Spike.swift, réduit à pid -> nom d'app)

    private func scanNotchApps(zone: CGRect, cadreEcran: CGRect) -> [(pid: pid_t, bundleID: String, name: String, cadre: CGRect)] {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: AnyObject]],
            let screenHeight = NSScreen.screens.first?.frame.height
        else { return [] }

        var seenPids = Set<pid_t>()
        var results: [(pid_t, String, String, CGRect)] = []

        for entry in list {
            guard
                let pidNum = entry[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                let layer = entry[kCGWindowLayer as String] as? Int
            else { continue }

            if seenPids.contains(pidNum) { continue }

            let appName = (entry[kCGWindowOwnerName as String] as? String) ?? "?"
            // Un process sans bundleID (Window Server, agents non-app) n'a pas d'identité stable :
            // impossible de le relancer une fois quitté, impossible de mémoriser son verdict. Il
            // n'a donc rien à faire dans la liste, et cette règle remplace l'ancien repli par nom.
            guard let bundleID = NSRunningApplication(processIdentifier: pidNum)?.bundleIdentifier
            else { continue }
            if bundleID == ownBundleID || systemBundleIDs.contains(bundleID) { continue }

            // Une app d'encoche est structurellement un overlay flottant (kCGWindowLayer > 0,
            // au-dessus de kCGNormalWindowLevel) ; une fenêtre de document normale est à 0, et le
            // plein écran ne change pas son layer — donc ce test écarte aussi les fenêtres
            // plein écran (Discord, Arc) qui toucheraient le haut de l'écran.
            guard layer > 0 else { continue }

            // Une fenêtre d'encoche, et pas seulement une fenêtre qui effleure l'encoche : le
            // détail des trois conditions et les mesures qui les fondent sont dans
            // `estFenetreEncoche` (ControleurApps.swift). Même prédicat que le recomptage par pid,
            // sinon le scan et la vérification ne mesureraient plus la même chose.
            guard let cadre = cadreFenetreEncoche(
                zone, cadreEcran: cadreEcran, bounds: boundsDict, hauteurEcranPrincipal: screenHeight
            ) else { continue }

            seenPids.insert(pidNum)
            results.append((pidNum, bundleID, appName, cadre))
        }
        return results
    }

    // MARK: - Rafraîchissement : découverte + suivi par identité (pas seulement géométrie)

    /// Recale le modèle sur ce que le sondage vient de VOIR, plutôt que sur ce que Bouncer croit
    /// avoir fait. Isolée de tout état pour être vérifiable, même raison que `periodeDeRepos`.
    ///
    /// `isHiddenByUs` n'est pas une intention, c'est un constat : une app masquée n'a par
    /// construction aucune fenêtre dans l'encoche, c'est tout l'objet du masquage. La revoir dans
    /// le scan prouve donc que le masquage a été DÉFAIT — l'utilisateur l'a relancée à la main
    /// depuis le Dock, Spotlight ou le Launchpad, et macOS lève `kAXHidden` en la réactivant.
    /// Bouncer n'en est jamais informé : aucune notification ne dit « ton masquage vient de
    /// sauter », seul le recomptage le constate. C'est la règle du dépôt appliquée au drapeau
    /// lui-même — le seul verdict qui vaut est l'état réel resondé, jamais le code retour de
    /// l'action qui l'a produit.
    ///
    /// Ce n'était qu'un menu qui mentait tant que la bascule ne s'y fiait pas. Depuis qu'elle
    /// s'appuie sur `bundleIDActive`, qui écarte les apps marquées masquées, un drapeau resté
    /// vrai fait choisir « aucune app active » sur une app pourtant à l'écran : la bascule
    /// suivante en allume une seconde par-dessus, et l'encoche en porte DEUX — le seul problème
    /// que Bouncer existe pour éviter.
    ///
    /// Un process mort remet aussi le drapeau à faux : une app qui n'est plus là n'est masquée
    /// par personne, et la laisser marquée la faisait figurer parmi les « apps coincées » que
    /// `signalerRevocation` nomme à l'utilisateur.
    public nonisolated static func recaler(
        _ apps: [NotchAppInfo], vues: [String: pid_t], processVivant: (pid_t) -> Bool
    ) -> [NotchAppInfo] {
        apps.map { info in
            var info = info
            if let pid = vues[info.bundleID] {
                info.pid = pid
                info.isHiddenByUs = false
            } else if let pid = info.pid, !processVivant(pid) {
                info.pid = nil
                info.isHiddenByUs = false
            }
            return info
        }
    }

    /// Un tour de sondage : la géométrie est relue, les fenêtres recomptées, le modèle recalé sur
    /// ce qui est RÉELLEMENT à l'écran. Interne, parce que ce n'est pas une action d'utilisateur :
    /// le timer et les réveils système passent par ici, le menu par `refresh()`.
    func sonder() {
        guard let (zone, ecran, cadreEcran) = geometrie() else {
            publier(description: "Aucune encoche détectée sur cette machine.")
            // Écran débranché, résolution changée, session verrouillée : le `apps = []` d'avant
            // jetait AUSSI les apps qu'on venait de masquer, et avec elles le seul drapeau qui
            // permettait de les réafficher. Débrancher un écran ne doit pas faire oublier ce
            // qu'on a caché — c'est la même règle qu'en bas, appliquée au même endroit.
            apps.removeAll { !$0.isHiddenByUs }
            publierCadre(nil)
            noterEmpreinte("aucune-encoche")
            return
        }
        publier(description: "\(ecran) — \(zone)")
        let discovered = scanNotchApps(zone: zone, cadreEcran: cadreEcran)
        publierCadre(discovered.map(\.cadre).reduce(CGRect.null) { $0.union($1) })
        let vuesParBundleID = Dictionary(discovered.map { ($0.bundleID, $0) }, uniquingKeysWith: { premiere, _ in premiere })

        // Une entrée sort de la liste dès que son process est mort OU qu'il ne croise plus
        // l'encoche — SAUF si on l'a nous-mêmes masquée : dans ce cas plus aucune fenêtre ne
        // croise l'encoche par construction (c'est le but du masquage), donc la garder est
        // le seul moyen de pouvoir la réafficher. Sans cette exception, masquer une app la
        // ferait disparaître du menu et deviendrait irréversible.
        apps.removeAll { info in
            guard !info.isHiddenByUs else { return false }
            return vuesParBundleID[info.bundleID] == nil
        }
        // Le cache n'a plus rien à purger : une clé bundleID reste valable même quand l'app est
        // arrêtée, et n'est jamais réattribuée à une autre app comme l'était un pid recyclé.

        // Le pid n'est plus une identité, seulement un état : il suit ce que dit la découverte, et
        // tombe à nil dès que le process a disparu — l'entrée, elle, reste. `isHiddenByUs` suit la
        // même règle, cf. `recaler`.
        apps = Self.recaler(
            apps,
            vues: vuesParBundleID.mapValues(\.pid),
            processVivant: { NSRunningApplication(processIdentifier: $0) != nil }
        )

        // Toute app vue dans le notch entre au catalogue, y compris celles qu'on ne connaissait
        // pas : c'est le seul moyen de la retrouver plus tard, une fois quittée et absente de
        // `CGWindowList`. Idempotent, donc pas de garde à ajouter ici.
        for (_, bundleID, _, _) in discovered {
            catalogue.apprendre(bundleID: bundleID)
        }

        for (pid, bundleID, name, _) in discovered where !apps.contains(where: { $0.bundleID == bundleID }) {
            if let cachedVerdict = supportVerdictCache[bundleID] {
                apps.append(NotchAppInfo(bundleID: bundleID, name: name, support: cachedVerdict, pid: pid, isHiddenByUs: false))
                continue
            }
            apps.append(NotchAppInfo(bundleID: bundleID, name: name, support: .testing, pid: pid, isHiddenByUs: false))
            // ponytail: constaté en test réel — un appel AXUIElementSetAttributeValue fait par ce
            // process AVANT l'octroi du trust laisse sa connexion Accessibility hors service pour
            // le reste de sa vie, même après que AXIsProcessTrusted() repasse à true (il faut alors
            // relancer l'app). On ne touche donc jamais l'API AX sans trust : les apps restent en
            // "Test en cours…" jusqu'au prochain retest déclenché par refreshTrustState().
            if accessibilityTrusted {
                // `testSupport` est asynchrone depuis que le masquage attend la propagation du
                // WindowServer par sondage plutôt qu'en bloquant. Le `Task` hérite du main actor —
                // l'app vient d'être ajoutée à `apps` avec le statut « Test en cours… », donc le
                // refresh suivant la voit déjà listée et ne relance pas un second test.
                Task { await testSupport(bundleID: bundleID, pid: pid) }
            }
        }

        // Tout ce qui, en changeant, doit ramener la cadence pleine : la liste des apps, leur
        // process, leur verdict, ce qu'on a masqué, et l'emprise des fenêtres sur l'encoche.
        noterEmpreinte(apps.map { "\($0.bundleID)/\($0.pid ?? -1)/\($0.support.rawValue)/\($0.isHiddenByUs)" }
            .joined(separator: "|") + "#\(cadreFenetresEncoche.map(String.init(describing:)) ?? "-")")
    }

    // MARK: - Masquage / vérification — déléguées au contrôleur (recomptage CGWindowList, jamais le code retour AX)

    /// Teste une app à sa découverte : masque, vérifie par recomptage, réaffiche, vérifie à nouveau.
    /// Ne laisse jamais l'app masquée à l'issue du test, que le test réussisse ou non.
    /// Le pid sert à agir (l'API AX ne connaît que lui), le bundleID à mémoriser le verdict.
    private func testSupport(bundleID: String, pid: pid_t) async {
        let hideOK = await controleur.masquer(true, pid: pid)
        let showOK = await controleur.masquer(false, pid: pid)
        let supported = hideOK && showOK
        let verdict: SupportStatus = supported ? .supported : .unsupported
        supportVerdictCache[bundleID] = verdict
        updateApp(bundleID: bundleID) {
            $0.support = verdict
            $0.isHiddenByUs = false
        }
    }

    // MARK: - Bascule : le point d'entrée unique du menu, du swipe et des flèches

    /// « Rends cette app active » : elle s'ouvre si elle est arrêtée, et celle qui occupait
    /// l'encoche est masquée ou quittée selon ce qu'elle accepte. C'est l'action du clic sur une
    /// entrée du menu, et c'est exactement celle du swipe — `cycle(forward:)` aboutit ici.
    ///
    /// Synchrone pour ses appelants (un bouton SwiftUI, un callback AppKit) ; le travail part dans
    /// une tâche, parce que la voie par cycle de vie attend l'apparition d'une fenêtre.
    public func rendreActive(bundleID: String) {
        Task { await basculer(vers: bundleID) }
    }

    /// La même bascule, attendable — c'est la forme qu'utilise un appelant déjà asynchrone.
    public func basculer(vers bundleID: String) async {
        // Un second geste pendant la bascule éteindrait l'app que le premier vient d'allumer.
        // Le menu marque déjà l'entrée en cours ; ici on se contente de refuser le doublon.
        guard bundleIDEnCoursDeBascule == nil else { return }
        guard let cible = infoPourBascule(bundleID) else { return }
        let actuelle = bundleIDActive.flatMap(infoPourBascule)

        bundleIDEnCoursDeBascule = bundleID
        echecBascule = nil
        let resultat = await bascule.basculer(vers: cible, depuis: actuelle)
        bundleIDEnCoursDeBascule = nil

        switch resultat {
        case .reussie:
            appliquerReussite(cible: cible.bundleID, actuelle: actuelle?.bundleID)
        case .precedenteResteEnPlace:
            // La cible EST dans l'encoche : cette moitié-là a réussi et doit être enregistrée.
            // Mais on ne dit rien de la précédente — `actuelle: nil` — parce que la seule chose
            // qu'`appliquerReussite` sait faire d'elle est la marquer `isHiddenByUs`, et elle ne
            // l'est pas : elle est toujours à l'écran. Le `refresh()` qui suit la reverra dans
            // l'encoche et la listera pour ce qu'elle est, une app lancée et visible.
            appliquerReussite(cible: cible.bundleID, actuelle: nil)
            let restee = actuelle?.name ?? cible.name
            echecBascule = "\(restee) n'a pas pu être quittée — elle attend probablement une réponse à l'écran (« Enregistrer les modifications ? »). Répondez-lui, puis réessayez : Bouncer ne la forcera pas, ce serait perdre votre travail."
        case .lancementImpossible:
            echecBascule = "\(cible.name) n'a pas pu être lancée."
        case .accessibiliteJamaisAccordee:
            // Le menu affiche déjà sa ligne « ⚠️ Autoriser dans les Réglages… » — `accessibilityTrusted`
            // est faux par définition dans ce cas. Ce message-ci porte ce qu'elle ne dit pas : que
            // le geste qu'on vient de faire n'a rien produit, et pourquoi.
            echecBascule = "Bouncer n'a pas encore l'accès à l'Accessibilité : sans lui, basculer quitterait \(cible.name) au lieu de la masquer. Autorisez Bouncer dans les Réglages Système, puis réessayez."
        case .cibleJamaisApparue:
            let repli = actuelle.map { "\($0.name) reste en place." } ?? "L'encoche est inchangée."
            // Une bascule qui traverse un changement d'écrans sonde une encoche qui n'existe
            // plus : elle expire donc au bout du délai, sans que la cible y soit pour quoi que ce
            // soit. Accuser l'app d'un débranchement d'écran envoie l'utilisateur la déboguer
            // pour rien.
            echecBascule = geometrie() == nil
                ? "Plus aucune encoche détectée — la bascule vers \(cible.name) a été abandonnée. \(repli)"
                : "\(cible.name) s'est lancée sans rien afficher dans l'encoche. \(repli)"
        }
    }

    /// L'app telle que la bascule doit la connaître. Une app arrêtée n'est pas dans `apps` — c'est
    /// toute la raison d'être du catalogue — on la fabrique donc à partir de lui, avec le verdict
    /// mémorisé s'il en existe un. Sans verdict, `.testing` envoie la bascule sur la voie cycle de
    /// vie, la seule qui marche tant qu'on ignore si l'app se laisse masquer.
    private func infoPourBascule(_ bundleID: String) -> NotchAppInfo? {
        if let app = apps.first(where: { $0.bundleID == bundleID }) { return app }
        guard let installee = catalogue.installees().first(where: { $0.bundleID == bundleID })
        else { return nil }
        return NotchAppInfo(
            bundleID: bundleID, name: installee.nom,
            support: supportVerdictCache[bundleID] ?? .testing,
            pid: controleur.pid(pour: bundleID), isHiddenByUs: false
        )
    }

    /// Recale le modèle après une bascule réussie. Une seule chose est mesurée — la cible occupe-
    /// t-elle l'encoche — parce que `.reussie` recouvre deux issues : le passage d'une app à une
    /// autre, et l'interrupteur sur une app seule au catalogue, qui vient au contraire de
    /// l'éteindre.
    private func appliquerReussite(cible: String, actuelle: String?) {
        let cibleVisible = controleur.pid(pour: cible)
            .map { controleur.fenetreVisibleDansNotch(pid: $0) } ?? false

        // Marqué AVANT le refresh : une app masquée n'a plus de fenêtre dans l'encoche, donc le
        // scan ne la voit plus, et c'est ce drapeau qui empêche `refresh()` de la retirer de la
        // liste — sans lui elle serait masquée sans retour possible. Une app quittée, elle, n'a
        // plus de pid : elle sort de `apps`, et le catalogue la garde au menu.
        if let actuelle, actuelle != cible, controleur.pid(pour: actuelle) != nil {
            updateApp(bundleID: actuelle) { $0.isHiddenByUs = true }
        }
        updateApp(bundleID: cible) { $0.isHiddenByUs = !cibleVisible }
        activeCycleBundleID = cibleVisible ? cible : nil
        sonder()
    }

    /// L'app qui occupe le notch : celle que la dernière bascule a désignée si elle est toujours
    /// lancée, sinon la première app lancée que nous n'avons pas masquée. Tant qu'aucune bascule
    /// n'a eu lieu, plusieurs apps peuvent être visibles à la fois — le menu marque alors la
    /// première, exactement comme le cycle choisit son point de départ.
    public var bundleIDActive: String? {
        if let id = activeCycleBundleID, apps.contains(where: { $0.bundleID == id && $0.estLancee }) {
            return id
        }
        return apps.first(where: { $0.estLancee && !$0.isHiddenByUs })?.bundleID
    }

    /// Les lignes du menu : les apps détectées, plus les apps du catalogue qui ne tournent pas.
    ///
    /// ponytail: `catalogue.installees()` interroge LaunchServices pour chaque bundleID connu.
    /// C'est une propriété calculée plutôt qu'un `@Published` recalculé au refresh parce que
    /// AUCUN de ses appelants ne l'évalue en continu :
    ///   - `MenuBarContentView` (l. 28) : menu ouvert seulement ;
    ///   - `cyclableApps`, donc chaque cran de swipe et chaque clic de flèche — que le seuil de
    ///     défilement et le cooldown de `NotchOverlay` limitent à quelques-uns par seconde ;
    ///   - `VueAccueil` (`FenetreAccueil.swift:132`) : à chaque rendu de la fenêtre d'accueil,
    ///     qui ne s'ouvre qu'au premier lancement ou depuis le menu ;
    ///   - l'onglet Applications des réglages (`FenetreReglages.swift:326`) : à chaque rendu de
    ///     l'onglet, donc fenêtre de réglages ouverte.
    /// Les deux derniers sont des vues SwiftUI : « à chaque rendu » veut dire à chaque changement
    /// d'état observé, pas à intervalle fixe. Si le catalogue grossit au point que l'ouverture du
    /// menu, le swipe ou la frappe dans les réglages se sentent, le mettre en cache dans
    /// `CatalogueApps` avec invalidation sur `apprendre`.
    public var entreesMenu: [EntreeMenu] {
        construireEntreesMenu(
            apps: apps,
            installees: catalogue.installees(),
            active: bundleIDActive,
            enCoursDeBascule: bundleIDEnCoursDeBascule
        )
    }

    // MARK: - Cycle circulaire (Milestone 2 : swipe / flèches)

    /// bundleID de l'app active du cycle swipe/flèches. Distinct de `isHiddenByUs` : plusieurs apps
    /// régissables peuvent être visibles à la fois (rien ne les a masquées), le cycle a besoin d'un
    /// point de départ explicite plutôt que de deviner "l'app active" depuis leur état de
    /// visibilité. Un bundleID plutôt qu'un pid : le point de départ survit à une app quittée.
    private var activeCycleBundleID: String?

    /// Les apps que le cycle parcourt : exactement les lignes du menu, dans le même ordre. Plus
    /// aucun filtre — ni sur le verdict, une app résistante participe désormais au cycle et c'est
    /// tout l'objet du chantier, ni sur l'état de lancement, puisque la bascule sait relancer une
    /// app arrêtée. Dérivé de `entreesMenu` plutôt que recalculé : le menu et le swipe doivent
    /// désigner la même « app suivante », sinon les deux gestes divergent sans rien signaler.
    /// Seule exception à cette identité, et elle est explicite : les apps que l'utilisateur a
    /// décochées dans les réglages sortent du cycle sans sortir du menu (cf. `bundleIDsCyclables`).
    var cyclableApps: [String] {
        bundleIDsCyclables(entrees: entreesMenu, exclus: reglages.bundleIDsExclus)
    }

    /// Le cycle a-t-il au moins une cible ? Les flèches ‹ › s'y adossent : quand l'utilisateur a
    /// décoché toutes les apps dans les réglages, `cycle` sort sur une liste vide et un clic ne
    /// fait rien — mieux vaut alors ne pas montrer de flèche du tout.
    public var cycleAUneCible: Bool { !cyclableApps.isEmpty }

    /// Un cran de swipe, ou un clic sur une flèche : l'app suivante (ou précédente) du cycle
    /// circulaire devient active, par la bascule qu'emprunte aussi le menu. Une seule app au
    /// catalogue redonne l'interrupteur d'origine, la bascule d'une app sur elle-même. No-op si
    /// le catalogue est vide.
    public func cycle(forward: Bool) {
        guard let suivant = prochaineCible(dans: cyclableApps, depuis: bundleIDActive, forward: forward)
        else {
            // Un cycle vide ne rendait rien du tout : le swipe passait pour non détecté, et
            // l'utilisateur réessayait. Les deux causes ne se corrigent pas au même endroit —
            // l'une s'installe, l'autre se recoche dans les réglages — donc on les distingue.
            echecBascule = entreesMenu.isEmpty
                ? "Aucune app d'encoche détectée. Lancez-en une pour que Bouncer l'apprenne."
                : "Toutes les apps d'encoche sont décochées dans les réglages."
            return
        }
        rendreActive(bundleID: suivant)
    }

    private func updateApp(bundleID: String, _ mutate: (inout NotchAppInfo) -> Void) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        mutate(&apps[idx])
    }
}
