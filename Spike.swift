#!/usr/bin/env swift
//
// Spike.swift — Milestone 0 : preuve de faisabilité pour Bouncer.
// Usage : swift Spike.swift [--pid <N>]
// Aucune dépendance externe. AppKit + ApplicationServices + CoreGraphics uniquement.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func log(_ msg: String) {
    print(msg)
    fflush(stdout)
}

func section(_ title: String) {
    log("\n=== \(title) ===")
}

// MARK: - Étape A : Droits Accessibilité

func checkAccessibility() -> Bool {
    section("A. Vérification des droits Accessibilité")
    let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    let trusted = AXIsProcessTrustedWithOptions(opts)
    if trusted {
        log("✅ Accessibilité déjà accordée.")
    } else {
        log("❌ Accessibilité refusée ou en attente.")
        log("   macOS a dû afficher une popup. Le binaire à autoriser dans")
        log("   Réglages Système > Confidentialité et sécurité > Accessibilité")
        log("   est le TERMINAL PARENT qui exécute ce script (ex: Terminal.app,")
        log("   iTerm2, ou le process 'swift'/'swift-frontend'), PAS ce fichier .swift.")
        log("   Autorise-le puis relance : swift Spike.swift")
    }
    return trusted
}

// MARK: - Étape B : Géométrie réelle de l'encoche

struct NotchZone {
    let rect: CGRect
    let sourceDescription: String
}

func getNotchZone() -> NotchZone {
    section("B. Géométrie de l'encoche")
    let screens = NSScreen.screens
    guard let primary = screens.first else {
        log("⚠️ Aucun NSScreen disponible, fallback bande 40pt.")
        return NotchZone(rect: CGRect(x: 0, y: 0, width: 800, height: 40), sourceDescription: "fallback (pas d'écran)")
    }

    // L'encoche physique n'est pas forcément sur NSScreen.main (= écran de la fenêtre
    // clé) : sur une machine multi-écrans, le MacBook interne avec encoche peut être
    // secondaire. On cherche le premier écran de la liste qui déclare une inset.
    guard let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
        log("ℹ️ Aucun écran avec safeAreaInsets.top > 0 → cette machine n'a pas d'encoche physique.")
        log("   Fallback : bande de 40pt en haut de l'écran principal, pleine largeur.")
        let frame = (NSScreen.main ?? primary).frame
        let rect = CGRect(x: frame.minX, y: frame.maxY - 40, width: frame.width, height: 40)
        return NotchZone(rect: rect, sourceDescription: "fallback (pas d'encoche détectée)")
    }

    let frame = notchScreen.frame
    let topInset = notchScreen.safeAreaInsets.top
    // Zones auxiliaires gauche/droite (l'espace de part et d'autre du capteur) :
    // déjà exprimées dans le repère AppKit global (bas-gauche = origine de l'écran
    // principal), pas dans le repère local de notchScreen.
    let leftArea = notchScreen.auxiliaryTopLeftArea ?? .zero
    let rightArea = notchScreen.auxiliaryTopRightArea ?? .zero
    log("Écran avec encoche : \(notchScreen.localizedName), frame = \(frame)")
    log("safeAreaInsets.top = \(topInset)pt")
    log("auxiliaryTopLeftArea  = \(leftArea)")
    log("auxiliaryTopRightArea = \(rightArea)")

    let notchMinX = leftArea != .zero ? leftArea.maxX : frame.midX - 100
    let notchMaxX = rightArea != .zero ? rightArea.minX : frame.midX + 100
    let notchWidth = max(notchMaxX - notchMinX, 1)
    let rect = CGRect(x: notchMinX, y: frame.maxY - topInset, width: notchWidth, height: topInset)
    log("✅ Zone d'encoche calculée (repère AppKit, origine bas-gauche de l'écran principal) : \(rect)")
    return NotchZone(rect: rect, sourceDescription: "safeAreaInsets + auxiliary areas sur \(notchScreen.localizedName)")
}

// MARK: - Étape C : Scan des fenêtres dans la zone d'encoche

struct WindowInfo {
    let index: Int
    let pid: pid_t
    let appName: String
    let title: String
    let bounds: CGRect
    let layer: Int
}

let systemProcessNames: Set<String> = [
    "Window Server", "Dock", "SystemUIServer", "Control Center", "Spotlight",
    "NotificationCenter", "WindowManager", "Notification Center",
]

func scanNotchWindows(notchZone: CGRect, ownPid: pid_t) -> [WindowInfo] {
    section("C. Scan des fenêtres dans la zone d'encoche")
    guard
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: AnyObject]]
    else {
        log("⚠️ CGWindowListCopyWindowInfo n'a rien retourné.")
        return []
    }

    var results: [WindowInfo] = []
    var idx = 0

    for entry in list {
        guard
            let pidNum = entry[kCGWindowOwnerPID as String] as? pid_t,
            let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
            let layer = entry[kCGWindowLayer as String] as? Int
        else { continue }

        if pidNum == ownPid { continue }

        let appName = (entry[kCGWindowOwnerName as String] as? String) ?? "?"
        if systemProcessNames.contains(appName) { continue }

        let bounds = CGRect(
            x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
        )

        // CGWindowListCopyWindowInfo rend les bounds en repère "haut-gauche = origine
        // de l'écran principal (celui qui porte la menu bar, NSScreen.screens[0])"
        // (contrairement à NSScreen, en "bas-gauche"). On convertit avant intersection.
        // NB : NSScreen.main (écran de la fenêtre clé) n'est PAS le bon repère ici —
        // seul screens[0] est la référence stable pour ce repère global Quartz.
        guard let screenHeight = NSScreen.screens.first?.frame.height else { continue }
        let boundsBottomLeftOrigin = CGRect(
            x: bounds.origin.x, y: screenHeight - bounds.origin.y - bounds.height,
            width: bounds.width, height: bounds.height
        )

        guard boundsBottomLeftOrigin.intersects(notchZone) else { continue }

        let title = (entry[kCGWindowName as String] as? String) ?? "(sans titre)"
        results.append(WindowInfo(index: idx, pid: pidNum, appName: appName, title: title, bounds: bounds, layer: layer))
        idx += 1
    }

    if results.isEmpty {
        log("Aucune fenêtre tierce détectée dans la zone d'encoche.")
    } else {
        // Le flag de largeur de String(format:) ne s'applique pas à %@ : padding manuel.
        func pad(_ s: String, _ n: Int) -> String {
            s.count >= n ? String(s.prefix(n - 1)) + " " : s.padding(toLength: n, withPad: " ", startingAt: 0)
        }
        log(pad("idx", 4) + pad("pid", 8) + pad("app", 22) + pad("titre", 24) + pad("bounds", 34) + "layer")
        for w in results {
            log(pad("\(w.index)", 4) + pad("\(w.pid)", 8) + pad(w.appName, 22)
                + pad(w.title, 24) + pad("\(w.bounds)", 34) + "\(w.layer)")
        }
    }
    return results
}

// MARK: - Étape D : Stratégies de masquage/réaffichage

enum HideStrategy: String {
    case axHiddenAttribute = "1. AXUIElementSetAttributeValue(kAXHiddenAttribute)"
    case runningApplication = "2. NSRunningApplication.hide()/unhide()"
    case axWindowMinimize = "3. Descente AX → kAXWindowsAttribute → kAXMinimizedAttribute"
}

struct StrategyResult {
    let strategy: HideStrategy
    let hideWorked: Bool
    let showWorked: Bool
    let hideMs: Double
    let showMs: Double
    let note: String
}

func timeMs(_ block: () -> Bool) -> (Double, Bool) {
    let start = CFAbsoluteTimeGetCurrent()
    let ok = block()
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
    return (elapsed, ok)
}

// Le succès d'un hide/show ne se juge PAS sur le code retour AX ni sur la relecture
// d'un attribut (kAXHiddenAttribute peut se relire à `true` alors que la fenêtre est
// toujours visible — faux positif observé sur boringNotch). La seule preuve fiable :
// la fenêtre du PID a disparu / est réapparue dans CGWindowListCopyWindowInfo.
func countWindows(forPid pid: pid_t) -> Int {
    guard
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: AnyObject]]
    else { return 0 }
    return list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }.count
}

func tryAXHiddenAttribute(pid: pid_t) -> StrategyResult {
    let appElement = AXUIElementCreateApplication(pid)
    let countBefore = countWindows(forPid: pid)

    let (hideMs, hideSet) = timeMs {
        AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success
    }
    usleep(300_000) // laisser le temps au WindowServer de propager l'état
    let countAfterHide = countWindows(forPid: pid)
    let hideConfirmed = countAfterHide < countBefore

    let (showMs, showSet) = timeMs {
        AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanFalse) == .success
    }
    usleep(300_000)
    let countAfterShow = countWindows(forPid: pid)
    let showConfirmed = countAfterShow >= countBefore

    return StrategyResult(
        strategy: .axHiddenAttribute,
        hideWorked: hideSet && hideConfirmed, showWorked: showSet && showConfirmed,
        hideMs: hideMs, showMs: showMs,
        note: "AXUIElementSetAttributeValue hide=\(hideSet) show=\(showSet) — confirmé via recomptage CGWindowList (avant=\(countBefore), après hide=\(countAfterHide), après show=\(countAfterShow)), PAS via relecture kAXHiddenAttribute"
    )
}

func tryNSRunningApplication(pid: pid_t) -> StrategyResult {
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        return StrategyResult(strategy: .runningApplication, hideWorked: false, showWorked: false, hideMs: 0, showMs: 0, note: "NSRunningApplication introuvable pour ce pid")
    }
    let countBefore = countWindows(forPid: pid)

    let (hideMs, hideCalled) = timeMs { app.hide() }
    usleep(300_000)
    let countAfterHide = countWindows(forPid: pid)
    let hideConfirmed = countAfterHide < countBefore

    let (showMs, showCalled) = timeMs { app.unhide() }
    usleep(300_000)
    let countAfterShow = countWindows(forPid: pid)
    let showConfirmed = countAfterShow >= countBefore

    return StrategyResult(
        strategy: .runningApplication,
        hideWorked: hideCalled && hideConfirmed, showWorked: showCalled && showConfirmed,
        hideMs: hideMs, showMs: showMs,
        note: "app.hide()/unhide() — confirmé via recomptage CGWindowList (avant=\(countBefore), après hide=\(countAfterHide), après show=\(countAfterShow)), PAS via NSRunningApplication.isHidden"
    )
}

func tryAXWindowMinimize(pid: pid_t) -> StrategyResult {
    let appElement = AXUIElementCreateApplication(pid)
    var windowsValue: AnyObject?
    AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

    guard let windows = windowsValue as? [AXUIElement], let window = windows.first else {
        return StrategyResult(strategy: .axWindowMinimize, hideWorked: false, showWorked: false, hideMs: 0, showMs: 0, note: "kAXWindowsAttribute vide ou inaccessible — probable NSPanel .nonactivatingPanel non exposé en AX")
    }
    let countBefore = countWindows(forPid: pid)

    let (hideMs, hideSet) = timeMs {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }
    usleep(300_000)
    let countAfterHide = countWindows(forPid: pid)
    let hideConfirmed = countAfterHide < countBefore

    let (showMs, showSet) = timeMs {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
    }
    usleep(300_000)
    let countAfterShow = countWindows(forPid: pid)
    let showConfirmed = countAfterShow >= countBefore

    return StrategyResult(
        strategy: .axWindowMinimize,
        hideWorked: hideSet && hideConfirmed, showWorked: showSet && showConfirmed,
        hideMs: hideMs, showMs: showMs,
        note: "kAXMinimizedAttribute sur la fenêtre AX trouvée — confirmé via recomptage CGWindowList (avant=\(countBefore), après hide=\(countAfterHide), après show=\(countAfterShow))"
    )
}

func runStrategyCycle(pid: pid_t) {
    section("D. Cycle masquer → attendre → réafficher, 3 stratégies")
    let strategies: [(HideStrategy, (pid_t) -> StrategyResult)] = [
        (.axHiddenAttribute, tryAXHiddenAttribute),
        (.runningApplication, tryNSRunningApplication),
        (.axWindowMinimize, tryAXWindowMinimize),
    ]

    var anyWorked = false
    for (kind, fn) in strategies {
        log("\n→ Stratégie \(kind.rawValue)")
        let r = fn(pid)
        log("   hide: \(r.hideWorked ? "✅" : "❌") en \(String(format: "%.1f", r.hideMs))ms")
        log("   show: \(r.showWorked ? "✅" : "❌") en \(String(format: "%.1f", r.showMs))ms")
        log("   note: \(r.note)")
        if r.hideWorked && r.showWorked { anyWorked = true }
    }

    if !anyWorked {
        log("\n⚠️ Aucune des 3 stratégies n'a fonctionné de bout en bout sur ce pid.")
        log("   Piste suivante à explorer (NON implémentée ici) : API privée SkyLight")
        log("   (CGSSetWindowAlpha) ou déplacement d'espace (CGSMoveWindowsToManagedSpace).")
    }
}

// MARK: - Main

let args = CommandLine.arguments
let ownPid = ProcessInfo.processInfo.processIdentifier

_ = checkAccessibility()
let notch = getNotchZone()
let windows = scanNotchWindows(notchZone: notch.rect, ownPid: ownPid)

var targetPid: pid_t? = nil
if let pidFlagIndex = args.firstIndex(of: "--pid"), args.count > pidFlagIndex + 1,
    let parsed = Int32(args[pidFlagIndex + 1])
{
    targetPid = parsed
} else if windows.count == 1 {
    targetPid = windows[0].pid
    log("\nUne seule fenêtre candidate détectée, sélection automatique : pid \(targetPid!)")
} else if !windows.isEmpty {
    log("\nCibles disponibles : \(windows.map { "\($0.index)=\($0.appName)(pid \($0.pid))" }.joined(separator: ", "))")
    log("Entre un index (ou lance avec --pid <N>) : ")
    if let line = readLine(), let chosenIndex = Int(line), windows.indices.contains(chosenIndex) {
        targetPid = windows[chosenIndex].pid
    } else {
        log("Pas d'entrée valide reçue, on prend la première fenêtre candidate par défaut.")
        targetPid = windows[0].pid
    }
}

if let pid = targetPid {
    runStrategyCycle(pid: pid)
} else {
    log("\n⚠️ Aucune fenêtre d'encoche détectée sur cette machine — étape D non testable ici.")
    log("   Lance une app comme Boring Notch ou Vibe Island, puis relance ce script.")
}
