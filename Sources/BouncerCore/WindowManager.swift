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
private let systemBundleIDs: Set<String> = [
    "com.apple.notificationcenterui", "com.apple.controlcenter", "com.apple.dock",
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

    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private var timer: Timer?

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

    /// `startTimer: false` pour le self-test CLI (un seul refresh() synchrone, pas de boucle).
    public init(
        startTimer: Bool = true,
        catalogue: CatalogueApps = CatalogueApps(),
        controleur: ControleurApps = ControleurAppsSysteme()
    ) {
        self.catalogue = catalogue
        self.controleur = controleur
        bascule = Bascule(controleur: controleur)
        accessibilityTrusted = AXIsProcessTrusted()
        if !accessibilityTrusted {
            // Popup système une seule fois, ici, à froid — jamais dans la boucle de refresh.
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as NSDictionary
            )
        }
        refresh()
        guard startTimer else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // Le timer est planifié sur la run loop principale : son callback s'exécute donc
            // déjà sur le main actor, `assumeIsolated` ne fait que le dire au compilateur.
            MainActor.assumeIsolated { self?.refreshTrustState() }
        }
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
        accessibilityTrusted = nowTrusted

        guard justGranted else {
            refresh()
            return
        }

        // ponytail: AXIsProcessTrusted() bascule à true avant que le serveur Accessibility
        // n'ait fini de propager côté API AX (constaté empiriquement : jusqu'à ~1s de
        // décalage) — un retest synchrone à l'instant du flip peut donc figer un faux "Non
        // supportée". On jette les verdicts et on laisse une seconde de marge avant de
        // retester. Si le décalage réel dépasse cette marge, prévoir un retry supplémentaire.
        apps.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
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
        guard let (rect, ecran) = zoneEncoche() else {
            lastNotchZoneDescription = "Aucune encoche détectée sur cette machine."
            return nil
        }
        lastNotchZoneDescription = "\(ecran) — \(rect)"
        return rect
    }

    // MARK: - Scan (portée depuis Spike.swift, réduit à pid -> nom d'app)

    private func scanNotchApps(zone: CGRect) -> [(pid: pid_t, bundleID: String, name: String)] {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: AnyObject]],
            let screenHeight = NSScreen.screens.first?.frame.height
        else { return [] }

        var seenPids = Set<pid_t>()
        var results: [(pid_t, String, String)] = []

        for entry in list {
            guard
                let pidNum = entry[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                let layer = entry[kCGWindowLayer as String] as? Int
            else { continue }

            if pidNum == ownPid || seenPids.contains(pidNum) { continue }

            let appName = (entry[kCGWindowOwnerName as String] as? String) ?? "?"
            // Un process sans bundleID (Window Server, agents non-app) n'a pas d'identité stable :
            // impossible de le relancer une fois quitté, impossible de mémoriser son verdict. Il
            // n'a donc rien à faire dans la liste, et cette règle remplace l'ancien repli par nom.
            guard let bundleID = NSRunningApplication(processIdentifier: pidNum)?.bundleIdentifier
            else { continue }
            if systemBundleIDs.contains(bundleID) { continue }

            // Une app d'encoche est structurellement un overlay flottant (kCGWindowLayer > 0,
            // au-dessus de kCGNormalWindowLevel) ; une fenêtre de document normale est à 0, et le
            // plein écran ne change pas son layer — donc ce test écarte aussi les fenêtres
            // plein écran (Discord, Arc) qui toucheraient le haut de l'écran.
            guard layer > 0 else { continue }

            guard croiseZoneEncoche(zone, bounds: boundsDict, hauteurEcranPrincipal: screenHeight)
            else { continue }

            seenPids.insert(pidNum)
            results.append((pidNum, bundleID, appName))
        }
        return results
    }

    // MARK: - Rafraîchissement : découverte + suivi par identité (pas seulement géométrie)

    public func refresh() {
        guard let zone = notchZone() else {
            apps = []
            return
        }
        let discovered = scanNotchApps(zone: zone)
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
        // tombe à nil dès que le process a disparu — l'entrée, elle, reste.
        for idx in apps.indices {
            if let vue = vuesParBundleID[apps[idx].bundleID] {
                apps[idx].pid = vue.pid
            } else if let pid = apps[idx].pid, NSRunningApplication(processIdentifier: pid) == nil {
                apps[idx].pid = nil
            }
        }

        // Toute app vue dans le notch entre au catalogue, y compris celles qu'on ne connaissait
        // pas : c'est le seul moyen de la retrouver plus tard, une fois quittée et absente de
        // `CGWindowList`. Idempotent, donc pas de garde à ajouter ici.
        for (_, bundleID, _) in discovered {
            catalogue.apprendre(bundleID: bundleID)
        }

        for (pid, bundleID, name) in discovered where !apps.contains(where: { $0.bundleID == bundleID }) {
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
                testSupport(bundleID: bundleID, pid: pid)
            }
        }
    }

    // MARK: - Masquage / vérification — déléguées au contrôleur (recomptage CGWindowList, jamais le code retour AX)

    /// Teste une app à sa découverte : masque, vérifie par recomptage, réaffiche, vérifie à nouveau.
    /// Ne laisse jamais l'app masquée à l'issue du test, que le test réussisse ou non.
    /// Le pid sert à agir (l'API AX ne connaît que lui), le bundleID à mémoriser le verdict.
    private func testSupport(bundleID: String, pid: pid_t) {
        let hideOK = controleur.masquer(true, pid: pid)
        let showOK = controleur.masquer(false, pid: pid)
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
        case .lancementImpossible:
            echecBascule = "\(cible.name) n'a pas pu être lancée."
        case .cibleJamaisApparue:
            let repli = actuelle.map { "\($0.name) reste en place." } ?? "L'encoche est inchangée."
            echecBascule = "\(cible.name) s'est lancée sans rien afficher dans l'encoche. \(repli)"
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
        refresh()
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
    /// C'est une propriété calculée plutôt qu'un `@Published` recalculé au refresh parce que ses
    /// deux appelants sont rares : le corps du menu n'est évalué que menu ouvert, et `cyclableApps`
    /// à chaque cran de swipe — que le seuil de défilement et le cooldown de `NotchOverlay`
    /// limitent à quelques-uns par seconde. Si le catalogue grossit au point que l'ouverture du
    /// menu ou le swipe se sentent, le mettre en cache dans `CatalogueApps` avec invalidation
    /// sur `apprendre`.
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
    var cyclableApps: [String] { entreesMenu.map(\.bundleID) }

    /// Un cran de swipe, ou un clic sur une flèche : l'app suivante (ou précédente) du cycle
    /// circulaire devient active, par la bascule qu'emprunte aussi le menu. Une seule app au
    /// catalogue redonne l'interrupteur d'origine, la bascule d'une app sur elle-même. No-op si
    /// le catalogue est vide.
    public func cycle(forward: Bool) {
        guard let suivant = prochaineCible(dans: cyclableApps, depuis: bundleIDActive, forward: forward)
        else { return }
        rendreActive(bundleID: suivant)
    }

    private func updateApp(bundleID: String, _ mutate: (inout NotchAppInfo) -> Void) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        mutate(&apps[idx])
    }
}
