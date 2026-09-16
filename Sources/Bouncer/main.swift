//
// main.swift — point d'entrée.
//
// La sortie de `--self-test` est un outil de développeur, pas de l'interface : elle est écrite
// en anglais et ne passe PAS par le catalogue de chaînes — la localiser reviendrait à traduire
// une table de diagnostic qu'on lit dans un terminal, et le README la cite déjà en anglais. `--self-test` fait tourner WindowManager en CLI (un seul
// sondage synchrone, table imprimée sur stdout) sans passer par la boucle SwiftUI/MenuBarExtra :
// utile pour vérifier la détection + le cycle masquer/réafficher depuis ce binaire précis, puisque
// l'autorisation Accessibilité se donne par binaire, pas par processus parent (cf. SPIKE_RESULTS.md).

import SwiftUI
import BouncerCore
import Sentry

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
    // Le catalogue en premier : `Bundle.module` fait un `fatalError` quand le bundle de
    // ressources n'est pas à côté du binaire — c'est le piège du packaging (cf. build.sh),
    // et il vaut mieux le voir ici que sur le premier menu ouvert.
    print("Strings: \(catalogueDeChaines.preferredLocalizations.first ?? "none") — \(texte("menu.settings"))")
    print("Accessibility granted to this binary: \(wm.accessibilityTrusted)")
    print("Notch zone: \(wm.lastNotchZoneDescription)")
    if wm.apps.isEmpty {
        print("No notch app found.")
    } else {
        for app in wm.apps {
            let pid = app.pid.map(String.init) ?? "—"
            print("bundle=\(app.bundleID)\tapp=\(app.name)\tpid=\(pid)\trunning=\(app.estLancee)\tstatus=\(app.support.rawValue)\thidden=\(app.isHiddenByUs)")
        }
    }
    exit(0)
    }
}

// Error monitoring seul (pas de tracing/profiling) — jamais sur le chemin --self-test au-dessus :
// ce mode est un outil de développeur lancé en boucle depuis un terminal, pas une session
// utilisateur, et il n'a pas vocation à remonter des events.
SentrySDK.start { options in
    options.dsn = "https://df3cae4a19aed384f3763d1e27ab0e12@o4511827012419584.ingest.de.sentry.io/4512097601847376"
    options.debug = false
    // Bouncer est distribué en Cask public sans écran de consentement : pas d'IP, pas de device
    // context nominatif dans les events.
    options.sendDefaultPii = false
    options.environment = "production"
    options.releaseName = "bouncer@\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")"
}

BouncerApp.main()
