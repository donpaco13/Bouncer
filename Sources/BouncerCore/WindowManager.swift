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

public final class WindowManager: ObservableObject {
    @Published public private(set) var apps: [NotchAppInfo] = []
    @Published public private(set) var accessibilityTrusted: Bool = false
    @Published public private(set) var lastNotchZoneDescription: String = "—"

    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private var timer: Timer?

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

    /// `startTimer: false` pour le self-test CLI (un seul refresh() synchrone, pas de boucle).
    public init(startTimer: Bool = true, catalogue: CatalogueApps = CatalogueApps()) {
        self.catalogue = catalogue
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
            self?.refreshTrustState()
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
    public func notchZone() -> CGRect? {
        let screens = NSScreen.screens
        guard let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            lastNotchZoneDescription = "Aucune encoche détectée sur cette machine."
            return nil
        }
        let frame = notchScreen.frame
        let topInset = notchScreen.safeAreaInsets.top
        let leftArea = notchScreen.auxiliaryTopLeftArea ?? .zero
        let rightArea = notchScreen.auxiliaryTopRightArea ?? .zero
        let notchMinX = leftArea != .zero ? leftArea.maxX : frame.midX - 100
        let notchMaxX = rightArea != .zero ? rightArea.minX : frame.midX + 100
        let notchWidth = max(notchMaxX - notchMinX, 1)
        let rect = CGRect(x: notchMinX, y: frame.maxY - topInset, width: notchWidth, height: topInset)
        lastNotchZoneDescription = "\(notchScreen.localizedName) — \(rect)"
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

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
            )
            let boundsBottomLeftOrigin = CGRect(
                x: bounds.origin.x, y: screenHeight - bounds.origin.y - bounds.height,
                width: bounds.width, height: bounds.height
            )
            guard boundsBottomLeftOrigin.intersects(zone) else { continue }

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

    // MARK: - Masquage / vérification (identique à Spike.swift : recomptage CGWindowList, jamais le code retour AX)

    private func countWindows(forPid pid: pid_t) -> Int {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: AnyObject]]
        else { return 0 }
        return list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }.count
    }

    @discardableResult
    private func setHidden(_ hidden: Bool, pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        let countBefore = countWindows(forPid: pid)
        AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, hidden ? kCFBooleanTrue : kCFBooleanFalse)
        usleep(300_000) // laisser le WindowServer propager, cf. Spike.swift
        let countAfter = countWindows(forPid: pid)
        return hidden ? countAfter < countBefore : countAfter >= countBefore
    }

    /// Teste une app à sa découverte : masque, vérifie par recomptage, réaffiche, vérifie à nouveau.
    /// Ne laisse jamais l'app masquée à l'issue du test, que le test réussisse ou non.
    /// Le pid sert à agir (l'API AX ne connaît que lui), le bundleID à mémoriser le verdict.
    private func testSupport(bundleID: String, pid: pid_t) {
        let hideOK = setHidden(true, pid: pid)
        let showOK = setHidden(false, pid: pid)
        let supported = hideOK && showOK
        let verdict: SupportStatus = supported ? .supported : .unsupported
        supportVerdictCache[bundleID] = verdict
        updateApp(bundleID: bundleID) {
            $0.support = verdict
            $0.isHiddenByUs = false
        }
    }

    /// Bascule manuelle (clic) : uniquement pour les apps régissables ET lancées — masquer une app
    /// arrêtée n'a pas de sens, et l'API AX n'a rien à cibler sans pid.
    public func toggle(bundleID: String) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }),
              apps[idx].support == .supported,
              let pid = apps[idx].pid
        else { return }
        let wantHidden = !apps[idx].isHiddenByUs
        if setHidden(wantHidden, pid: pid) {
            apps[idx].isHiddenByUs = wantHidden
        }
    }

    // MARK: - Cycle circulaire (Milestone 2 : swipe / flèches)

    /// bundleID de l'app active du cycle swipe/flèches. Distinct de `isHiddenByUs` : plusieurs apps
    /// régissables peuvent être visibles à la fois (rien ne les a masquées), le cycle a besoin d'un
    /// point de départ explicite plutôt que de deviner "l'app active" depuis leur état de
    /// visibilité. Un bundleID plutôt qu'un pid : le point de départ survit à une app quittée.
    private var activeCycleBundleID: String?

    /// Apps utilisables dans le cycle swipe/flèches — régissables et lancées, jamais les
    /// "Non supportée" (cf. consigne M2). Le filtre sur `estLancee` tombera à la Task 5, quand la
    /// bascule saura relancer une app arrêtée ; aujourd'hui le cycle ne sait que masquer/réafficher.
    var cyclableApps: [NotchAppInfo] { apps.filter { $0.support == .supported && $0.estLancee } }

    /// Une bascule = masque l'app active courante, montre la suivante (ou précédente) du cycle
    /// circulaire. No-op s'il n'y a rien à basculer.
    public func cycle(forward: Bool) {
        let cyclable = cyclableApps
        if cyclable.isEmpty { return }

        if cyclable.count == 1 {
            toggle(bundleID: cyclable[0].bundleID)
            return
        }

        let ids = cyclable.map(\.bundleID)
        let courant = activeCycleBundleID ?? cyclable.first(where: { !$0.isHiddenByUs })?.bundleID ?? ids[0]
        guard ids.contains(courant) else {
            activeCycleBundleID = ids[0]
            return
        }
        guard let suivant = prochaineCible(dans: ids, depuis: courant, forward: forward), suivant != courant
        else { return }

        if let pid = pid(pour: courant), setHidden(true, pid: pid) {
            updateApp(bundleID: courant) { $0.isHiddenByUs = true }
        }
        if let pid = pid(pour: suivant), setHidden(false, pid: pid) {
            updateApp(bundleID: suivant) { $0.isHiddenByUs = false }
        }
        activeCycleBundleID = suivant
    }

    private func pid(pour bundleID: String) -> pid_t? {
        apps.first(where: { $0.bundleID == bundleID })?.pid
    }

    private func updateApp(bundleID: String, _ mutate: (inout NotchAppInfo) -> Void) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        mutate(&apps[idx])
    }
}
