//
// CatalogueApps.swift — les apps de notch INSTALLÉES, lancées ou non.
//
// `CGWindowList` ne montre que ce qui est à l'écran : une app qu'on vient de quitter en disparaît,
// or c'est précisément celle qu'on voudra relancer à la bascule suivante. Il faut donc une source
// de vérité qui survit à l'arrêt d'un process — le disque.
//
// Bouncer apprend : toute app découverte une fois dans le notch voit son bundleID mémorisé.
// Le catalogue vaut (bundleIDs appris ∪ liste d'amorçage) ∩ apps réellement présentes sur le
// disque. L'amorçage sert au tout premier lancement, avant tout apprentissage ; passé ce cap,
// c'est l'apprentissage qui porte le catalogue, y compris pour des apps de notch qu'on ne
// connaissait pas.

import AppKit
import Foundation

/// Apps de notch connues d'avance, pour le premier lancement.
///
/// Les deux bundleIDs ci-dessous ont été relevés dans le `Info.plist` des apps installées sur la
/// machine de développement — ce ne sont pas des suppositions. Alcove et Notchy manquent
/// volontairement : elles ne sont installées sur aucune machine à laquelle on a accès, donc leur
/// bundleID ne serait qu'une devinette, et une devinette fausse ne fait rien (elle ne résout pas)
/// tout en donnant l'illusion d'une couverture. L'apprentissage les rattrapera à leur première
/// apparition dans le notch ; les ajouter ici demande seulement de relever leur identifiant réel.
/// bundleID -> nom d'affichage. Le nom sert à l'accueil de première ouverture, qui doit pouvoir
/// nommer une app d'encoche ABSENTE de la machine (donc introuvable sur le disque, donc sans nom
/// à en tirer). Une seule table pour les deux usages : une liste de noms écrite à part finirait
/// par diverger de la liste de bundleIDs.
public let appsEncocheConnues: [String: String] = [
    "app.vibeisland.macos": "Vibe Island",
    "theboringteam.boringnotch": "boringNotch",
]

public let amorcageCatalogue: Set<String> = Set(appsEncocheConnues.keys)

/// Une app de notch présente sur le disque. Rien sur son état d'exécution : le catalogue dit ce
/// qui est installable/lançable, pas ce qui tourne — c'est `WindowManager` qui sait ça.
public struct AppInstallee: Equatable {
    public let bundleID: String
    public let nom: String
    public let url: URL
}

public final class CatalogueApps {
    /// Où trouver une app à partir de son bundleID. Injecté plutôt qu'appelé en dur, sinon le
    /// contenu du catalogue dépend des apps installées sur la machine qui lance les tests.
    public typealias Resolveur = (String) -> URL?

    private static let cleApprises = "bouncer.bundleIDsApprises"

    private let defaults: UserDefaults
    private let amorcage: Set<String>
    private let resolveur: Resolveur

    public init(
        defaults: UserDefaults = .standard,
        amorcage: Set<String> = amorcageCatalogue,
        resolveur: @escaping Resolveur = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) {
        self.defaults = defaults
        self.amorcage = amorcage
        self.resolveur = resolveur
    }

    /// Les bundleIDs déjà vus dans le notch, toutes sessions confondues.
    public var apprises: Set<String> {
        Set(defaults.stringArray(forKey: Self.cleApprises) ?? [])
    }

    /// Mémorise une app aperçue dans le notch. Idempotent : appelable à chaque découverte sans
    /// se demander si elle est déjà connue.
    public func apprendre(bundleID: String) {
        let deja = apprises
        guard !deja.contains(bundleID) else { return }
        defaults.set(deja.union([bundleID]).sorted(), forKey: Self.cleApprises)
    }

    /// (appris ∪ amorçage) ∩ disque. Une app désinstallée sort du catalogue mais reste apprise :
    /// la réinstaller la ramène sans qu'il faille la revoir dans le notch.
    ///
    /// Trié par nom : le cycle swipe avance dans l'ordre de cette liste, et cet ordre doit être
    /// le même d'une session à l'autre — sinon « l'app suivante » change de sens au redémarrage.
    public func installees() -> [AppInstallee] {
        apprises.union(amorcage)
            .compactMap { bundleID in
                resolveur(bundleID).map {
                    AppInstallee(bundleID: bundleID, nom: $0.deletingPathExtension().lastPathComponent, url: $0)
                }
            }
            .sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
    }
}
