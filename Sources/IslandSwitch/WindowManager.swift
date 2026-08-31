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

enum SupportStatus: String {
    case testing = "Test en cours…"
    case supported = "Régissable"
    case unsupported = "Non supportée"
}

struct NotchAppInfo: Identifiable, Equatable {
    var id: pid_t { pid }
    let pid: pid_t
    let bundleID: String?
    let name: String
    var support: SupportStatus
    var isHiddenByUs: Bool
}

/// Processus systèmes à ignorer dans le scan de la zone d'encoche (identique à Spike.swift).
private let systemProcessNames: Set<String> = [
    "Window Server", "Dock", "SystemUIServer", "Control Center", "Spotlight",
    "NotificationCenter", "WindowManager", "Notification Center",
]

final class WindowManager: ObservableObject {
    @Published private(set) var apps: [NotchAppInfo] = []
    @Published private(set) var accessibilityTrusted: Bool = false
    @Published private(set) var lastNotchZoneDescription: String = "—"

    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private var timer: Timer?

    /// `startTimer: false` pour le self-test CLI (un seul refresh() synchrone, pas de boucle).
    init(startTimer: Bool = true) {
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
    func openAccessibilitySettings() {
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

    private func notchZone() -> CGRect? {
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

    private func scanNotchPids(zone: CGRect) -> [(pid: pid_t, name: String)] {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: AnyObject]],
            let screenHeight = NSScreen.screens.first?.frame.height
        else { return [] }

        var seenPids = Set<pid_t>()
        var results: [(pid_t, String)] = []

        for entry in list {
            guard
                let pidNum = entry[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            if pidNum == ownPid || seenPids.contains(pidNum) { continue }

            let appName = (entry[kCGWindowOwnerName as String] as? String) ?? "?"
            if systemProcessNames.contains(appName) { continue }

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
            results.append((pidNum, appName))
        }
        return results
    }

    // MARK: - Rafraîchissement : découverte + suivi par identité (pas seulement géométrie)

    func refresh() {
        guard let zone = notchZone() else {
            apps = []
            return
        }
        let discovered = scanNotchPids(zone: zone)

        // Un process qui a quitté est retiré même s'il n'intersectait plus la zone au moment
        // de sa disparition (cf. TECH_SPEC/consigne : le suivi se fait par identité de process,
        // pas seulement par intersection géométrique instantanée).
        apps.removeAll { info in NSRunningApplication(processIdentifier: info.pid) == nil }

        for (pid, name) in discovered where !apps.contains(where: { $0.pid == pid }) {
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            apps.append(NotchAppInfo(pid: pid, bundleID: bundleID, name: name, support: .testing, isHiddenByUs: false))
            // ponytail: constaté en test réel — un appel AXUIElementSetAttributeValue fait par ce
            // process AVANT l'octroi du trust laisse sa connexion Accessibility hors service pour
            // le reste de sa vie, même après que AXIsProcessTrusted() repasse à true (il faut alors
            // relancer l'app). On ne touche donc jamais l'API AX sans trust : les apps restent en
            // "Test en cours…" jusqu'au prochain retest déclenché par refreshTrustState().
            if accessibilityTrusted {
                testSupport(pid: pid)
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
    private func testSupport(pid: pid_t) {
        let hideOK = setHidden(true, pid: pid)
        let showOK = setHidden(false, pid: pid)
        let supported = hideOK && showOK
        updateApp(pid: pid) {
            $0.support = supported ? .supported : .unsupported
            $0.isHiddenByUs = false
        }
    }

    /// Bascule manuelle (clic) : uniquement pour les apps régissables. Ignore les non supportées.
    func toggle(pid: pid_t) {
        guard let idx = apps.firstIndex(where: { $0.pid == pid }), apps[idx].support == .supported else { return }
        let wantHidden = !apps[idx].isHiddenByUs
        if setHidden(wantHidden, pid: pid) {
            apps[idx].isHiddenByUs = wantHidden
        }
    }

    private func updateApp(pid: pid_t, _ mutate: (inout NotchAppInfo) -> Void) {
        guard let idx = apps.firstIndex(where: { $0.pid == pid }) else { return }
        mutate(&apps[idx])
    }
}
