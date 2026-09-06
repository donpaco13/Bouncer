//
// TraceSwipe.swift — le journal qui rend le geste OBSERVABLE.
//
// Pourquoi il existe. Trois bugs de swipe ont été résolus dans ce projet en enregistrant un flux
// d'événements réel, et deux correctifs posés au jugé avaient échoué avant. Le point aveugle qui
// restait : on ne voyait que les événements ACCEPTÉS. Un geste qui ne déclenche rien ne laissait
// aucune trace, donc rien à lire. Ce journal note d'abord POURQUOI un événement a été écarté, et
// par quel garde — sans ça, un swipe raté est un silence, et un silence ne se débogue pas.
//
// Éteint par défaut, et pas seulement pour le coût : un journal qui tourne en permanence sur 86
// événements par geste remplit un disque sans que personne le lise. On l'allume pour une session
// de mesure, on relit, on éteint :
//
//     defaults write io.github.donpaco13.bouncer bouncer.traceSwipe -bool true    # puis relancer Bouncer
//     tail -f ~/Library/Logs/Bouncer/swipe.log
//     defaults write io.github.donpaco13.bouncer bouncer.traceSwipe -bool false
//
// Écrit en TSV et non en JSON : ces lignes se lisent à l'œil et se trient à l'`awk`, et c'est ce
// qu'on en fait. L'écriture est différée sur une file dédiée — le journal ne doit pas ajouter de
// latence au geste qu'il mesure.

import Foundation

public enum TraceSwipe {
    public static let clePreference = "bouncer.traceSwipe"
    public static let bundleIDReel = "io.github.donpaco13.bouncer"
    public static let variableEnvironnement = "BOUNCER_TRACE_SWIPE"

    /// Détermine si l'instrumentation est active pour un domaine de préférences et un environnement donnés.
    public static func estActif(
        defaults: UserDefaults = .standard,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        defaults.bool(forKey: clePreference) || env[variableEnvironnement] == "1"
    }

    /// Lu une seule fois au démarrage : le drapeau ne change pas en cours de vie, et le relire à
    /// chaque événement mettrait `UserDefaults` sur le chemin critique du geste.
    /// La variable d'environnement double la préférence pour une raison pratique : un binaire de
    /// développement lancé hors bundle n'a pas de domaine `UserDefaults` stable, donc
    /// `defaults write` n'y arrive pas — et c'est justement le binaire sur lequel on mesure.
    public static let active: Bool = estActif()

    private static let file = DispatchQueue(label: "com.bouncer.trace", qos: .utility)
    private static let debut = Date()

    public static let chemin: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Bouncer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("swipe.log")
    }()

    /// Note une ligne, horodatée en secondes depuis le lancement — c'est l'écart entre deux
    /// événements qui dit quelque chose, pas l'heure murale.
    public static func note(_ champs: String...) {
        guard active else { return }
        let t = Date().timeIntervalSince(debut)
        let ligne = (["\(String(format: "%.4f", t))"] + champs).joined(separator: "\t") + "\n"
        file.async {
            guard let data = ligne.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: chemin) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: chemin)
            }
        }
    }
}
