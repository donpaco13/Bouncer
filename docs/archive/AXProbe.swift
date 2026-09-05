#!/usr/bin/env swift
//
// AXProbe.swift — Enquête AX sur les apps récalcitrantes (suite du Milestone 0).
// Usage : swift AXProbe.swift --pid <N>
// Aucune dépendance externe. AppKit + ApplicationServices + CoreGraphics uniquement.
//
// Objectif : dumper l'arbre AX complet d'un process cible (attributs application +
// attributs de chaque fenêtre, avec leur valeur et leur caractère settable), puis
// tester une par une les propriétés plausibles de masquage trouvées comme settables,
// en mesurant l'effet RÉEL via recomptage CGWindowList — jamais via le code retour AX
// ni la relecture d'attribut (cf. faux positif kAXHiddenAttribute sur boringNotch,
// documenté dans SPIKE_RESULTS.md).
//
// Ce script restaure systématiquement l'état original de chaque attribut testé :
// il est exécuté contre des apps réelles utilisées au quotidien.

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

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? String(s.prefix(n - 1)) + " " : s.padding(toLength: n, withPad: " ", startingAt: 0)
}

// MARK: - Primitives AX

func attributeNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let err = AXUIElementCopyAttributeNames(element, &names)
    guard err == .success, let arr = names as? [String] else { return [] }
    return arr
}

func attributeValue(_ element: AXUIElement, _ attr: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    return err == .success ? value : nil
}

func isSettable(_ element: AXUIElement, _ attr: String) -> Bool {
    var settable: DarwinBoolean = false
    let err = AXUIElementIsAttributeSettable(element, attr as CFString, &settable)
    return err == .success && settable.boolValue
}

func describeValue(_ value: AnyObject?) -> String {
    guard let value = value else { return "<nil>" }
    if let b = value as? Bool { return b ? "true" : "false" }
    if CFGetTypeID(value) == AXValueGetTypeID() {
        let axVal = value as! AXValue
        switch AXValueGetType(axVal) {
        case .cgPoint:
            var p = CGPoint.zero; AXValueGetValue(axVal, .cgPoint, &p); return "CGPoint\(p)"
        case .cgSize:
            var s = CGSize.zero; AXValueGetValue(axVal, .cgSize, &s); return "CGSize\(s)"
        case .cgRect:
            var r = CGRect.zero; AXValueGetValue(axVal, .cgRect, &r); return "CGRect\(r)"
        case .cfRange:
            var rg = CFRange(location: 0, length: 0); AXValueGetValue(axVal, .cfRange, &rg)
            return "CFRange(\(rg.location),\(rg.length))"
        default:
            return "<AXValue type inconnu>"
        }
    }
    if CFGetTypeID(value) == AXUIElementGetTypeID() { return "<AXUIElement>" }
    if let arr = value as? [AnyObject] { return "[array de \(arr.count)]" }
    if let s = value as? String { return "\"\(s)\"" }
    if let n = value as? NSNumber { return "\(n)" }
    return "\(value)"
}

func axErrorName(_ err: AXError) -> String {
    switch err {
    case .success: return "success"
    case .failure: return "failure"
    case .illegalArgument: return "illegalArgument"
    case .invalidUIElement: return "invalidUIElement"
    case .invalidUIElementObserver: return "invalidUIElementObserver"
    case .cannotComplete: return "cannotComplete"
    case .attributeUnsupported: return "attributeUnsupported"
    case .actionUnsupported: return "actionUnsupported"
    case .notificationUnsupported: return "notificationUnsupported"
    case .notImplemented: return "notImplemented"
    case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
    case .notificationNotRegistered: return "notificationNotRegistered"
    case .apiDisabled: return "apiDisabled"
    case .noValue: return "noValue"
    case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: return "notEnoughPrecision"
    @unknown default: return "unknown(\(err.rawValue))"
    }
}

// Seul juge de vérité : le recomptage des fenêtres réellement affichées pour ce pid.
// Jamais le code retour AX, jamais la relecture d'attribut (cf. bug 2 de Spike.swift).
func countWindows(forPid pid: pid_t) -> Int {
    guard
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: AnyObject]]
    else { return 0 }
    return list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }.count
}

// MARK: - Dump complet d'un élément AX

func dumpElement(_ element: AXUIElement, label: String) {
    section("Dump AX — \(label)")
    let names = attributeNames(element)
    if names.isEmpty {
        log("(aucun attribut exposé)")
        return
    }
    for name in names.sorted() {
        let value = attributeValue(element, name)
        let settable = isSettable(element, name)
        log("  \(pad(name, 28)) [settable=\(settable ? "✅" : "❌")] = \(describeValue(value))")
    }
}

func getWindows(appElement: AXUIElement) -> [AXUIElement] {
    guard let value = attributeValue(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else {
        return []
    }
    return value
}

// MARK: - Résultat de test

struct ProbeResult {
    let attribute: String
    let testValue: String
    let effectWorked: Bool
    let restoreWorked: Bool
    let elapsedMs: Double
    let note: String
}

func printResult(_ r: ProbeResult) {
    log("\n→ \(r.attribute)  (valeur testée : \(r.testValue))")
    log("   effet (masque la fenêtre) : \(r.effectWorked ? "✅" : "❌")  en \(String(format: "%.1f", r.elapsedMs))ms")
    log("   restauration               : \(r.restoreWorked ? "✅" : "❌")")
    log("   note: \(r.note)")
}

// MARK: - Tests spécifiques

// kAXHiddenAttribute et kAXMinimizedAttribute au niveau FENÊTRE (pas application —
// déjà couvert par Spike.swift stratégie 1/3). Générique car les deux sont booléens.
func testBooleanAttribute(pid: pid_t, window: AXUIElement, attr: String, levelNote: String) -> ProbeResult {
    guard let originalValue = attributeValue(window, attr) else {
        return ProbeResult(attribute: attr, testValue: "-", effectWorked: false, restoreWorked: true, elapsedMs: 0,
                            note: "valeur originale illisible sur cet élément — test ignoré (\(levelNote))")
    }
    let originalBool = (originalValue as? Bool) ?? false
    let countBefore = countWindows(forPid: pid)

    let start = CFAbsoluteTimeGetCurrent()
    let setOk = AXUIElementSetAttributeValue(
        window, attr as CFString, (originalBool ? kCFBooleanFalse : kCFBooleanTrue) as CFTypeRef
    ) == .success
    usleep(300_000)
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
    let countAfter = countWindows(forPid: pid)
    let worked = countAfter < countBefore

    _ = AXUIElementSetAttributeValue(window, attr as CFString, (originalBool ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    usleep(300_000)
    let countRestored = countWindows(forPid: pid)

    return ProbeResult(
        attribute: attr, testValue: "toggle bool (orig=\(originalBool))",
        effectWorked: worked, restoreWorked: countRestored == countBefore, elapsedMs: elapsed,
        note: "\(levelNote) — AXSetAttributeValue ok=\(setOk) — CGWindowList avant=\(countBefore) après=\(countAfter) restauré=\(countRestored)"
    )
}

func testWindowSize(pid: pid_t, window: AXUIElement) -> ProbeResult {
    let attr = kAXSizeAttribute as String
    guard let originalValue = attributeValue(window, attr), CFGetTypeID(originalValue) == AXValueGetTypeID() else {
        return ProbeResult(attribute: attr, testValue: "-", effectWorked: false, restoreWorked: true, elapsedMs: 0,
                            note: "valeur originale illisible — test ignoré")
    }
    var originalSize = CGSize.zero
    AXValueGetValue(originalValue as! AXValue, .cgSize, &originalSize)

    let countBefore = countWindows(forPid: pid)
    var tiny = CGSize(width: 1, height: 1)
    guard let tinyValue = AXValueCreate(.cgSize, &tiny) else {
        return ProbeResult(attribute: attr, testValue: "1x1", effectWorked: false, restoreWorked: true, elapsedMs: 0, note: "AXValueCreate a échoué")
    }

    let start = CFAbsoluteTimeGetCurrent()
    let setOk = AXUIElementSetAttributeValue(window, attr as CFString, tinyValue) == .success
    usleep(300_000)
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
    let countAfter = countWindows(forPid: pid)
    let worked = countAfter < countBefore

    var orig = originalSize
    if let origValue = AXValueCreate(.cgSize, &orig) {
        _ = AXUIElementSetAttributeValue(window, attr as CFString, origValue)
    }
    usleep(300_000)
    let countRestored = countWindows(forPid: pid)

    return ProbeResult(
        attribute: attr, testValue: "1x1 (orig \(originalSize))",
        effectWorked: worked, restoreWorked: countRestored == countBefore, elapsedMs: elapsed,
        note: "AXSetAttributeValue ok=\(setOk) — CGWindowList avant=\(countBefore) après=\(countAfter) restauré=\(countRestored)"
    )
}

// Point précis demandé par l'orchestrateur : la position seule ne cache pas la
// fenêtre (déjà "non concluant" dans Spike), mais on relit ICI la position juste
// après le set — avant toute restauration — pour savoir si l'app la réimpose
// elle-même (télémétrie différente de l'effet de masquage).
func testWindowPosition(pid: pid_t, window: AXUIElement) -> ProbeResult {
    let attr = kAXPositionAttribute as String
    guard let originalValue = attributeValue(window, attr), CFGetTypeID(originalValue) == AXValueGetTypeID() else {
        return ProbeResult(attribute: attr, testValue: "-", effectWorked: false, restoreWorked: true, elapsedMs: 0,
                            note: "valeur originale illisible — test ignoré")
    }
    var originalPos = CGPoint.zero
    AXValueGetValue(originalValue as! AXValue, .cgPoint, &originalPos)

    let countBefore = countWindows(forPid: pid)
    var offscreen = CGPoint(x: -10000, y: -10000)
    guard let offscreenValue = AXValueCreate(.cgPoint, &offscreen) else {
        return ProbeResult(attribute: attr, testValue: "off-screen", effectWorked: false, restoreWorked: true, elapsedMs: 0, note: "AXValueCreate a échoué")
    }

    let start = CFAbsoluteTimeGetCurrent()
    let setOk = AXUIElementSetAttributeValue(window, attr as CFString, offscreenValue) == .success
    usleep(300_000)
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
    let countAfter = countWindows(forPid: pid)
    let worked = countAfter < countBefore

    var readBackPos = CGPoint.zero
    var selfRestoredNote = "lecture après-set impossible"
    if let readBack = attributeValue(window, attr), CFGetTypeID(readBack) == AXValueGetTypeID() {
        AXValueGetValue(readBack as! AXValue, .cgPoint, &readBackPos)
        let driftFromTarget = abs(readBackPos.x - offscreen.x) > 1 || abs(readBackPos.y - offscreen.y) > 1
        selfRestoredNote = driftFromTarget
            ? "position relue = \(readBackPos) ≠ cible \(offscreen) → l'app a réimposé sa propre position"
            : "position relue = \(readBackPos) = cible → l'app a accepté le déplacement sans le corriger"
    }

    var orig = originalPos
    if let origValue = AXValueCreate(.cgPoint, &orig) {
        _ = AXUIElementSetAttributeValue(window, attr as CFString, origValue)
    }
    usleep(300_000)
    let countRestored = countWindows(forPid: pid)

    return ProbeResult(
        attribute: attr, testValue: "off-screen \(offscreen) (orig \(originalPos))",
        effectWorked: worked, restoreWorked: countRestored == countBefore, elapsedMs: elapsed,
        note: "setOk=\(setOk) — \(selfRestoredNote) — CGWindowList avant=\(countBefore) après=\(countAfter) restauré=\(countRestored)"
    )
}

func reportRoleAndSubrole(_ window: AXUIElement, label: String) {
    let role = attributeValue(window, kAXRoleAttribute as String) as? String ?? "<indisponible>"
    let subrole = attributeValue(window, kAXSubroleAttribute as String) as? String ?? "<indisponible>"
    log("\(label) → kAXRoleAttribute = \"\(role)\", kAXSubroleAttribute = \"\(subrole)\"")
}

// Attributs connus déjà couverts par un test dédié ci-dessus, ou volontairement
// exclus (focus/sélection : les activer peut voler le focus à d'autres apps sans
// rapport avec le masquage — pas une piste plausible, juste un risque de side-effect).
let coveredOrExcluded: Set<String> = [
    kAXHiddenAttribute as String, kAXMinimizedAttribute as String,
    kAXSizeAttribute as String, kAXPositionAttribute as String,
    kAXFocusedAttribute as String, kAXMainAttribute as String,
    kAXRoleAttribute as String, kAXSubroleAttribute as String,
    kAXFrontmostAttribute as String,
]

// Découverte : tout AUTRE attribut settable et booléen révélé par le dump — piste
// plausible de masquage non anticipée par la liste ci-dessus.
func discoverExtraBooleanCandidates(_ window: AXUIElement) -> [String] {
    var found: [String] = []
    for name in attributeNames(window) {
        if coveredOrExcluded.contains(name) { continue }
        guard isSettable(window, name) else { continue }
        guard let value = attributeValue(window, name), (value as? Bool) != nil else { continue }
        found.append(name)
    }
    return found
}

// MARK: - Cycle complet pour un pid

func runProbe(pid: pid_t) {
    let appElement = AXUIElementCreateApplication(pid)

    dumpElement(appElement, label: "Application (pid \(pid))")

    let windows = getWindows(appElement: appElement)
    if windows.isEmpty {
        log("\n⚠️ kAXWindowsAttribute vide ou inaccessible pour ce pid — aucun test au niveau fenêtre possible.")
        return
    }
    log("\n\(windows.count) fenêtre(s) trouvée(s) via kAXWindowsAttribute.")

    for (idx, w) in windows.enumerated() {
        dumpElement(w, label: "Window[\(idx)] (pid \(pid))")
        reportRoleAndSubrole(w, label: "Window[\(idx)]")
    }

    guard let window = windows.first else { return }

    section("Test des propriétés plausibles de masquage (fenêtre principale, pid \(pid))")

    var results: [ProbeResult] = []
    results.append(testBooleanAttribute(pid: pid, window: window, attr: kAXHiddenAttribute as String, levelNote: "niveau FENÊTRE"))
    results.append(testBooleanAttribute(pid: pid, window: window, attr: kAXMinimizedAttribute as String, levelNote: "niveau FENÊTRE — re-vérification de la stratégie 3 de Spike.swift"))
    results.append(testWindowSize(pid: pid, window: window))
    results.append(testWindowPosition(pid: pid, window: window))

    let extras = discoverExtraBooleanCandidates(window)
    if extras.isEmpty {
        log("\n(aucun attribut booléen settable additionnel découvert au-delà de la liste connue)")
    } else {
        log("\nAttributs booléens settable additionnels découverts par le dump : \(extras.joined(separator: ", "))")
        for attr in extras {
            results.append(testBooleanAttribute(pid: pid, window: window, attr: attr, levelNote: "découvert dynamiquement"))
        }
    }

    for r in results { printResult(r) }

    section("Résumé (pid \(pid))")
    log(pad("attribut", 26) + pad("effet masquage", 16) + pad("restauré", 10) + "temps")
    for r in results {
        log(pad(r.attribute, 26) + pad(r.effectWorked ? "✅" : "❌", 16) + pad(r.restoreWorked ? "✅" : "❌", 10) + "\(String(format: "%.1f", r.elapsedMs))ms")
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard let pidFlagIndex = args.firstIndex(of: "--pid"), args.count > pidFlagIndex + 1,
    let pid = Int32(args[pidFlagIndex + 1])
else {
    log("Usage: swift AXProbe.swift --pid <N>")
    exit(1)
}

let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
guard AXIsProcessTrustedWithOptions(opts) else {
    log("❌ Accessibilité non accordée au process qui exécute ce script (Terminal parent). Voir Spike.swift.")
    exit(1)
}

runProbe(pid: pid)
