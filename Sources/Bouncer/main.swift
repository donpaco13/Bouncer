//
// main.swift — point d'entrée. `--self-test` fait tourner WindowManager en CLI (un seul
// sondage synchrone, table imprimée sur stdout) sans passer par la boucle SwiftUI/MenuBarExtra :
// utile pour vérifier la détection + le cycle masquer/réafficher depuis ce binaire précis, puisque
// l'autorisation Accessibilité se donne par binaire, pas par processus parent (cf. SPIKE_RESULTS.md).

import SwiftUI
import BouncerCore

if CommandLine.arguments.contains("--self-test") {
    // Le code de haut niveau de `main.swift` n'est pas isolé, alors que `WindowManager` l'est
    // désormais au main actor. Il tourne bel et bien sur le thread principal : `assumeIsolated`
    // le déclare au compilateur au lieu d'introduire une hop asynchrone dans un chemin CLI.
    MainActor.assumeIsolated {
    let wm = WindowManager(startTimer: false)
    // Le sondage de construction lance le test de support dans une tâche : sans pomper la boucle principale, la
    // table s'imprimerait avec « Test en cours… » partout et ne mesurerait rien. On rend la main
    // dès que tous les verdicts sont tombés, et au plus tard au bout de 15 s (le pire cas connu
    // est une app par cycle de vie, ~1 s, mais une app qui ne répond pas fait attendre le timeout
    // de masquage sur chaque appel).
    let echeance = Date().addingTimeInterval(15)
    while wm.apps.contains(where: { $0.support == .testing }), Date() < echeance {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    print("Accessibilité accordée à ce binaire : \(wm.accessibilityTrusted)")
    print("Zone d'encoche : \(wm.lastNotchZoneDescription)")
    if wm.apps.isEmpty {
        print("Aucune app d'encoche détectée.")
    } else {
        for app in wm.apps {
            let pid = app.pid.map(String.init) ?? "—"
            print("bundle=\(app.bundleID)\tapp=\(app.name)\tpid=\(pid)\tlancée=\(app.estLancee)\tstatut=\(app.support.rawValue)\tmasquée=\(app.isHiddenByUs)")
        }
    }
    exit(0)
    }
}

BouncerApp.main()
