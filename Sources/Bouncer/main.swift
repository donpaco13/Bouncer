//
// main.swift — point d'entrée. `--self-test` fait tourner WindowManager en CLI (un seul
// refresh() synchrone, table imprimée sur stdout) sans passer par la boucle SwiftUI/MenuBarExtra :
// utile pour vérifier la détection + le cycle masquer/réafficher depuis ce binaire précis, puisque
// l'autorisation Accessibilité se donne par binaire, pas par processus parent (cf. SPIKE_RESULTS.md).

import SwiftUI

if CommandLine.arguments.contains("--self-test") {
    let wm = WindowManager(startTimer: false)
    print("Accessibilité accordée à ce binaire : \(wm.accessibilityTrusted)")
    print("Zone d'encoche : \(wm.lastNotchZoneDescription)")
    if wm.apps.isEmpty {
        print("Aucune app d'encoche détectée.")
    } else {
        for app in wm.apps {
            print("pid=\(app.pid)\tapp=\(app.name)\tbundle=\(app.bundleID ?? "?")\tstatut=\(app.support.rawValue)\tmasquée=\(app.isHiddenByUs)")
        }
    }
    exit(0)
}

IslandSwitchApp.main()
