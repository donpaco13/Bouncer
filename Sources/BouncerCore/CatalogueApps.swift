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
/// **La règle d'entrée : bundleID relevé dans un `Info.plist`, ET masquage mesuré sur la machine.**
/// Les sept ci-dessous viennent de la campagne du 5 septembre 2026 (`docs/COMPATIBILITE.md` §3.1 et
/// §3.2) : chacune a été installée, lancée, et son décompte de fenêtres relevé avant/pendant/après
/// un masquage. Aucune n'est une devinette, et une devinette fausse ne ferait rien tout en donnant
/// l'illusion d'une couverture. Les six apps de §3.3 — Alcove, SuperIsland, Atoll, DynamicNotch,
/// Droppy, MediaMate — ont pourtant leur bundleID relevé, et restent dehors : elles n'ont affiché
/// aucune surface d'encoche pendant la campagne, donc rien n'a été mesuré sur elles.
///
/// **Trois des sept ne peuvent PAS entrer par la découverte, et c'est pour elles que cette liste
/// compte.** NotchNook, Notchy et Mew Notch dessinent leur encoche sur toute la largeur de l'écran
/// (1352 pt sur 1352) — un profil que `estFenetreEncoche` refuse, et doit refuser, parce que c'est
/// aussi celui du Dock et de la barre de menus. Les nommer ici les rend régissables sans toucher au
/// filtre : le catalogue les tient, `couvreEncoche` les mesure par pid, et le scan de découverte
/// reste aussi strict qu'avant. C'est le chemin par lequel Bouncer passe de quatre apps régies à
/// sept sans réapprendre un seul faux positif.
///
/// bundleID -> nom d'affichage. Le nom sert à l'accueil de première ouverture, qui doit pouvoir
/// nommer une app d'encoche ABSENTE de la machine (donc introuvable sur le disque, donc sans nom
/// à en tirer). Une seule table pour les deux usages : une liste de noms écrite à part finirait
/// par diverger de la liste de bundleIDs.
public let appsEncocheConnues: [String: String] = [
    // Mesurées régies et vues par le scan (§3.1).
    "app.vibeisland.macos": "Vibe Island",
    "com.cyclop.app": "Cyclop",
    "company.gh.notch": "gh-notch",
    "theboringteam.boringnotch": "boringNotch",
    // Mesurées masquables, invisibles au scan : régies par leur seul bundleID (§3.2).
    "lo.cafe.NotchNook": "NotchNook",
    "dev.notchy.app": "Notchy",
    "com.monuk7735.mew.notch": "Mew Notch",
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

    /// La clé porte la version du filtre de détection qui a rempli le catalogue.
    ///
    /// Le `v2` n'est pas décoratif : ce qui a été appris sous l'ancien filtre — « la fenêtre
    /// effleure l'encoche » — l'a été à tort. Sur la machine de référence, ce catalogue-là
    /// contenait sept bundleIDs dont cinq intrus (Finder, Discord, Arc, iScreen Shoter, Munder
    /// Difflin), et le cycle de bascule emmenait l'utilisateur sur le Finder. Un apprentissage
    /// est définitif par construction, donc la seule façon honnête de jeter celui-là est de ne
    /// plus lire la clé qui le contient. L'ancienne est effacée au passage : la garder ne
    /// servirait qu'à faire grossir les préférences.
    /// Le `v3` suit la même règle, appliquée au filtre suivant. Le catalogue `v2` de la machine de
    /// référence contenait cinq bundleIDs dont TROIS intrus : `io.github.donpaco13.bouncer`
    /// (Bouncer elle-même — l'ancienne exclusion portait sur le pid, donc sur la seule instance
    /// courante), `com.apple.UserNotificationCenter` et `com.pais.handy` (fuite inter-écrans de
    /// `estFenetreEncoche`, mesurée le 5 septembre 2026). Les trois causes sont corrigées ; ce que
    /// le filtre fautif a appris, lui, ne se corrige pas tout seul, et un cycle de bascule qui
    /// emmène sur Bouncer ou sur le centre de notifications reste faux tant que la clé est lue.
    private static let cleApprises = "bouncer.bundleIDsApprises.v3"
    private static let clesApprisesObsoletes = ["bouncer.bundleIDsApprises", "bouncer.bundleIDsApprises.v2"]

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
        Self.clesApprisesObsoletes.forEach(defaults.removeObject(forKey:))
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
