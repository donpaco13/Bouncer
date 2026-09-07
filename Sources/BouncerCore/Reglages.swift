//
// Reglages.swift — les préférences de Bouncer, et rien d'autre.
//
// Chaque valeur ici était une constante en dur dans `NotchOverlay.swift` ou `WindowManager.swift`.
// Elles remontent parce qu'elles décident de la SENSATION du produit — la distance à laquelle les
// flèches s'allument, la largeur des bandes cliquables, la fréquence à laquelle l'app resonde le
// système — et que cette sensation n'appartient pas au code : elle appartient à celui qui s'en
// sert. Les défauts ci-dessous sont les valeurs mesurées ou raisonnées du code d'origine, pas des
// choix nouveaux.
//
// CE QUI N'EST DÉLIBÉRÉMENT PAS RÉGLABLE ICI, et pourquoi :
//
//   - Le SEUIL du `DetecteurSwipe` (6 pt) et sa fenêtre de repos (0,5 s). Mesuré le 2026-09-03 sur
//     un geste réel enregistré (cf. Swipe.swift) : 6, 8, 12 et 20 donnent EXACTEMENT le même
//     résultat, parce que ce qui découpe les gestes n'est pas la distance mais la phase du geste
//     physique (`arme`), qui n'a rien à régler. Un curseur « sensibilité du swipe » serait donc un
//     bouton qui rassure sans rien changer — la pire espèce de réglage : il déplace la faute sur
//     l'utilisateur quand le geste rate. La fenêtre de repos, elle, ne sert QU'aux périphériques
//     sans phase (molette classique), où le trackpad n'entre jamais.
//     Si un jour le seuil devient un levier — parce que la règle de découpage aura changé — il
//     entrera ici comme les autres. Pas avant.
//
//   - Le sens du swipe. Un swipe avance d'un cran quel que soit son sens (cf. Swipe.swift) : il
//     n'y a pas deux comportements entre lesquels choisir.
//
// Persistance : `UserDefaults`, injectable — sans quoi les tests écriraient dans les préférences
// réelles de la machine qui les lance.

import Combine
import CoreGraphics
import Foundation

/// Par quoi l'utilisateur fait tourner le cycle. Demande explicite : pouvoir n'avoir que l'un des
/// deux. Le trackpad n'est pas universel (souris externe), et les flèches ne plaisent pas à tout
/// le monde (elles s'allument au passage sur la barre des menus).
public enum ModeActivation: String, CaseIterable, Identifiable, Sendable {
    case lesDeux, swipeSeul, flechesSeules

    public var id: String { rawValue }

    public var swipeActif: Bool { self != .flechesSeules }
    public var flechesActives: Bool { self != .swipeSeul }

    public var libelle: String {
        switch self {
        case .lesDeux: return "Le swipe et les flèches"
        case .swipeSeul: return "Le swipe seul"
        case .flechesSeules: return "Les flèches seules"
        }
    }

    /// La conséquence concrète, pas la reformulation du libellé.
    public var explication: String {
        switch self {
        case .lesDeux:
            return "Swipe horizontal à deux doigts sur l'encoche, ou clic sur une flèche."
        case .swipeSeul:
            return "Aucune flèche ne s'affiche. Rien ne recouvre jamais la barre des menus."
        case .flechesSeules:
            return "Le swipe est ignoré. Utile avec une souris, ou si le geste part tout seul."
        }
    }
}

/// Sur quoi Bouncer cale sa géométrie : la zone qu'il écoute et l'endroit où il pose ses flèches.
///
/// MESURÉ le 2026-09-05 : le boîtier caméra fait 166 pt, la fenêtre d'une app d'encoche en fait
/// 640 (boringNotch) ou 740 (Vibe Island), et haute de 210 à 520 pt. Se caler sur le boîtier, c'est
/// écouter 2,7 % de ce que l'utilisateur voit et vise — d'où les swipes ratés. Le défaut se cale
/// donc sur la fenêtre. Le mode `boitier` reste, parce qu'il est la seule réponse quand aucune app
/// d'encoche n'est là, et le seul repli si la zone élargie attrape des gestes non voulus.
public enum AncrageZone: String, CaseIterable, Identifiable, Sendable {
    case fenetreEncoche, boitier

    public var id: String { rawValue }

    public var libelle: String {
        switch self {
        case .fenetreEncoche: return "La fenêtre de l'app d'encoche"
        case .boitier: return "Le boîtier caméra seul"
        }
    }

    public var explication: String {
        switch self {
        case .fenetreEncoche:
            return "Le swipe marche partout sur l'île qu'on voit, et les flèches se posent de part et d'autre. Sans app d'encoche à l'écran, revient au boîtier."
        case .boitier:
            return "Zone étroite, collée à l'encoche matérielle. À essayer si un défilement horizontal déclenche une bascule sans l'avoir voulu."
        }
    }
}

/// Les préférences, publiées vers SwiftUI et écrites au disque à chaque changement.
///
/// Une seule instance vit dans l'app (créée par `BouncerApp.init` et passée à qui en a besoin) :
/// deux instances liraient bien les mêmes clés, mais ne se préviendraient pas l'une l'autre, et
/// l'overlay ne verrait pas bouger ce que la fenêtre de réglages vient de changer.
public final class Reglages: ObservableObject {
    /// Bornes ET défauts au même endroit : le curseur de la fenêtre de réglages lit ces bornes,
    /// et `charge`/`ecris` s'en sert pour ramener dans le domaine une valeur écrite à la main
    /// dans les préférences (`defaults write`) ou héritée d'une version future.
    public enum Domaine {
        public static let portee: ClosedRange<CGFloat> = 0...200
        public static let porteeDefaut: CGFloat = 72

        public static let marge: ClosedRange<CGFloat> = 24...96
        public static let margeDefaut: CGFloat = 44

        /// De combien de points la flèche GLISSE vers l'extérieur pendant qu'elle se révèle.
        /// 0 = fondu seul, l'ancien comportement. 8 pt : assez pour que l'œil lise un
        /// déploiement, assez peu pour que la flèche reste dans sa marge sur tout le trajet.
        public static let retrait: ClosedRange<CGFloat> = 0...24
        public static let retraitDefaut: CGFloat = 8

        // --- Les quatre knobs des pistes « flèches propres » (2026-09-07). ---
        //
        // Ils N'APPARAISSENT PAS dans la fenêtre de réglages, et c'est délibéré : ce sont des
        // propositions en attente d'arbitrage, pas des réglages arrêtés. La sensation du geste et
        // le design appartiennent à François ; livrer quatre curseurs de plus reviendrait à
        // trancher à sa place et à figer dans l'UI ce qui n'est pas encore décidé.
        //
        // Chacun se règle sans recompiler, l'app relancée :
        //   defaults write io.github.donpaco13.bouncer bouncer.<clé> -float <valeur>
        // Le détail de chaque piste vit dans `docs/rapport-fleches-propres.html`.

        /// P2 — temps de présence dans la portée exigé avant que les chevrons se montrent.
        /// 0 = tout de suite, le comportement actuel.
        public static let delai: ClosedRange<TimeInterval> = 0...2
        public static let delaiDefaut: TimeInterval = 0

        /// P1 — temps d'immobilité après lequel les chevrons s'effacent, curseur toujours en
        /// place. 0 = jamais, le comportement actuel.
        public static let inactivite: ClosedRange<TimeInterval> = 0...20
        public static let inactiviteDefaut: TimeInterval = 0

        /// P3 — où le chevron se pose dans sa marge. 0 = collé au boîtier, 1 = au bord extérieur.
        public static let alignement: ClosedRange<CGFloat> = 0...1

        /// P4 — exposant de la courbe d'opacité. < 1 : devinable de loin. > 1 : discret jusqu'au
        /// dernier moment.
        public static let courbe: ClosedRange<CGFloat> = 0.3...3

        /// Pas un intervalle continu : un curseur suggérerait qu'une valeur intermédiaire a un
        /// sens, alors que le seul arbitrage est « réactivité contre travail à vide ».
        ///
        /// Ces cinq valeurs sont la période RAPIDE, celle qui vaut tant que quelque chose bouge.
        /// Au repos, `WindowManager` espace lui-même le sondage jusqu'à 8 s et le ramène à la
        /// période réglée au premier réveil (cf. l'addendum de `docs/PERFORMANCE.md`) : ce
        /// réglage arbitre la réactivité, plus le travail à vide, qui est déjà traité.
        /// Le défaut reste 2 s — c'est cette période qui fait avancer l'accueil tout seul au
        /// moment où l'utilisateur accorde l'Accessibilité.
        public static let intervalles: [TimeInterval] = [1, 2, 5, 10, 30]
        public static let intervalleDefaut: TimeInterval = 2
    }

    private enum Cle {
        static let mode = "bouncer.modeActivation"
        static let ancrage = "bouncer.ancrageZone"
        static let retrait = "bouncer.retraitFleches"
        static let portee = "bouncer.porteeApproche"
        static let marge = "bouncer.margeLaterale"
        static let intervalle = "bouncer.intervalleRafraichissement"
        static let exclus = "bouncer.bundleIDsExclus"
        static let raccourci = "bouncer.raccourciGlobal"
        static let delai = "bouncer.delaiRevelation"
        static let inactivite = "bouncer.inactiviteFleches"
        static let alignement = "bouncer.alignementFleches"
        static let courbe = "bouncer.courbeRevelation"
    }

    private let defaults: UserDefaults

    /// Ce qui déclenche le cycle : swipe, flèches, ou les deux.
    @Published public var modeActivation: ModeActivation {
        didSet { defaults.set(modeActivation.rawValue, forKey: Cle.mode) }
    }

    /// Sur quoi la zone sensible et les flèches se calent.
    @Published public var ancrageZone: AncrageZone {
        didSet { defaults.set(ancrageZone.rawValue, forKey: Cle.ancrage) }
    }

    /// La combinaison qui fait tourner le cycle depuis n'importe quelle app. `.aucun` n'enregistre
    /// rien du tout — voir `RaccourciGlobal` pour pourquoi ce choix doit rester à l'utilisateur.
    @Published public var raccourciGlobal: RaccourciGlobal {
        didSet { defaults.set(raccourciGlobal.rawValue, forKey: Cle.raccourci) }
    }

    // Les trois réglages bornés ci-dessous sont des propriétés CALCULÉES au-dessus d'un stockage
    // `@Published` privé, et non des `@Published` avec un `didSet` qui se corrige lui-même.
    //
    // MESURÉ, et ça a coûté un crash en réel (EXC_BAD_ACCESS, débordement de pile) : sur une
    // propriété STOCKÉE, se réassigner depuis son propre `didSet` ne rappelle pas `didSet` — mais
    // `@Published` est un property wrapper, donc la propriété est calculée, donc la réassignation
    // repasse par le setter et `didSet` se rappelle SANS FIN. Le curseur de la fenêtre de réglages
    // tuait l'app dès qu'on le bougeait. Borner à l'ENTRÉE supprime le cycle au lieu de le gérer.

    /// Distance, en points, à laquelle les flèches commencent à apparaître au-delà de la zone
    /// sensible. 0 = elles n'apparaissent qu'une fois le curseur dans la bande.
    /// C'était LA constante du projet restée réglée à l'œil (cf. NotchOverlay.swift).
    public var porteeApproche: CGFloat {
        get { porteeStockee }
        set { ecris(Self.borne(newValue, dans: Domaine.portee, sinon: porteeStockee),
                    dans: &porteeStockee, cle: Cle.portee) }
    }
    @Published private var porteeStockee: CGFloat

    /// Largeur de bande visible prise de chaque côté du boîtier caméra. C'est là que logent les
    /// flèches, et c'est aussi la surface de barre des menus que l'overlay couvre à l'approche.
    public var margeLaterale: CGFloat {
        get { margeStockee }
        set { ecris(Self.borne(newValue, dans: Domaine.marge, sinon: margeStockee),
                    dans: &margeStockee, cle: Cle.marge) }
    }
    @Published private var margeStockee: CGFloat

    /// Glissement des flèches pendant la révélation, en points.
    public var retraitFleches: CGFloat {
        get { retraitStocke }
        set { ecris(Self.borne(newValue, dans: Domaine.retrait, sinon: retraitStocke),
                    dans: &retraitStocke, cle: Cle.retrait) }
    }
    @Published private var retraitStocke: CGFloat

    /// P2 — temps de présence exigé avant la révélation, en secondes.
    public var delaiRevelation: TimeInterval {
        get { delaiStocke }
        set { ecris(Self.borneDuree(newValue, dans: Domaine.delai, sinon: delaiStocke),
                    dans: &delaiStocke, cle: Cle.delai) }
    }
    @Published private var delaiStocke: TimeInterval

    /// P1 — temps d'immobilité après lequel les chevrons s'effacent, en secondes.
    public var inactiviteFleches: TimeInterval {
        get { inactiviteStockee }
        set { ecris(Self.borneDuree(newValue, dans: Domaine.inactivite, sinon: inactiviteStockee),
                    dans: &inactiviteStockee, cle: Cle.inactivite) }
    }
    @Published private var inactiviteStockee: TimeInterval

    /// P3 — position du chevron dans sa marge (0 = collé au boîtier, 1 = bord extérieur).
    public var alignementFleches: CGFloat {
        get { alignementStocke }
        set { ecris(Self.borne(newValue, dans: Domaine.alignement, sinon: alignementStocke),
                    dans: &alignementStocke, cle: Cle.alignement) }
    }
    @Published private var alignementStocke: CGFloat

    /// P4 — exposant de la courbe d'opacité de la révélation.
    public var courbeRevelation: CGFloat {
        get { courbeStockee }
        set { ecris(Self.borne(newValue, dans: Domaine.courbe, sinon: courbeStockee),
                    dans: &courbeStockee, cle: Cle.courbe) }
    }
    @Published private var courbeStockee: CGFloat

    /// Les deux horloges sont-elles au repos ? Quand elles le sont — le défaut — l'overlay ne pose
    /// aucun timer et rien ne change du comportement d'aujourd'hui.
    public var revelationTemporelleActive: Bool { delaiStocke > 0 || inactiviteStockee > 0 }

    /// Période du resondage système (apps présentes dans l'encoche, autorisation Accessibilité).
    public var intervalleRafraichissement: TimeInterval {
        get { intervalleStocke }
        set {
            guard Domaine.intervalles.contains(newValue) else { return }
            ecris(newValue, dans: &intervalleStocke, cle: Cle.intervalle)
        }
    }
    @Published private var intervalleStocke: TimeInterval

    /// Le stockage étant privé, son publisher ne l'est pas : `WindowManager` doit reposer son
    /// timer sur la nouvelle période, et `objectWillChange` ne dirait pas laquelle des cinq
    /// préférences a bougé — il ferait replanifier le timer à chaque coup de curseur.
    public var changementsIntervalle: AnyPublisher<TimeInterval, Never> {
        $intervalleStocke.eraseToAnyPublisher()
    }

    /// Écrit la valeur et la persiste, en ne touchant à rien si elle n'a pas bougé — un curseur
    /// qu'on traîne repasse par ce setter à chaque point, et republier pour rien fait recalculer
    /// tout ce qui observe (l'overlay se reconstruit).
    private func ecris<T: Equatable>(_ valeur: T, dans stockage: inout T, cle: String) {
        guard valeur != stockage else { return }
        stockage = valeur
        // CGFloat n'est pas un type plist : `defaults.set(_:forKey:)` l'archiverait en NSNumber
        // via le pont Objective-C, mais on force le Double pour que la relecture
        // (`object(forKey:) as? Double`) retrouve exactement ce qu'on a écrit.
        defaults.set((valeur as? CGFloat).map(Double.init) ?? valeur, forKey: cle)
    }

    /// Apps que le cycle saute. Elles restent dans le menu et restent cliquables : exclure, c'est
    /// « ne me la propose pas au swipe », pas « oublie-la ». Le menu est l'endroit où l'on désigne
    /// une app explicitement — l'y retirer aussi rendrait l'exclusion irréversible sans repasser
    /// par les réglages.
    @Published public var bundleIDsExclus: Set<String> {
        didSet { defaults.set(bundleIDsExclus.sorted(), forKey: Cle.exclus) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modeActivation = (defaults.string(forKey: Cle.mode).flatMap(ModeActivation.init(rawValue:)))
            ?? .lesDeux
        // `object(forKey:)` et pas `double(forKey:)` : ce dernier rend 0 pour une clé absente, ce
        // qui est une valeur LÉGALE ici (portée nulle = pas de rampe). Sans cette distinction, un
        // premier lancement livrerait des flèches sans approche.
        porteeStockee = Self.borne(
            (defaults.object(forKey: Cle.portee) as? Double).map { CGFloat($0) },
            dans: Domaine.portee, sinon: Domaine.porteeDefaut
        )
        margeStockee = Self.borne(
            (defaults.object(forKey: Cle.marge) as? Double).map { CGFloat($0) },
            dans: Domaine.marge, sinon: Domaine.margeDefaut
        )
        retraitStocke = Self.borne(
            (defaults.object(forKey: Cle.retrait) as? Double).map { CGFloat($0) },
            dans: Domaine.retrait, sinon: Domaine.retraitDefaut
        )
        delaiStocke = Self.borneDuree(
            defaults.object(forKey: Cle.delai) as? Double,
            dans: Domaine.delai, sinon: Domaine.delaiDefaut
        )
        inactiviteStockee = Self.borneDuree(
            defaults.object(forKey: Cle.inactivite) as? Double,
            dans: Domaine.inactivite, sinon: Domaine.inactiviteDefaut
        )
        alignementStocke = Self.borne(
            (defaults.object(forKey: Cle.alignement) as? Double).map { CGFloat($0) },
            dans: Domaine.alignement, sinon: alignementFlechesDefaut
        )
        courbeStockee = Self.borne(
            (defaults.object(forKey: Cle.courbe) as? Double).map { CGFloat($0) },
            dans: Domaine.courbe, sinon: courbeRevelationDefaut
        )
        ancrageZone = (defaults.string(forKey: Cle.ancrage).flatMap(AncrageZone.init(rawValue:)))
            ?? .fenetreEncoche
        let lu = defaults.object(forKey: Cle.intervalle) as? Double
        intervalleStocke = lu.flatMap { Domaine.intervalles.contains($0) ? $0 : nil }
            ?? Domaine.intervalleDefaut
        bundleIDsExclus = Set(defaults.stringArray(forKey: Cle.exclus) ?? [])
        // Un rawValue inconnu (préférence écrite à la main, ou combinaison retirée d'une version
        // à l'autre) retombe sur le défaut plutôt que de laisser l'app sans raccourci du tout.
        raccourciGlobal = (defaults.string(forKey: Cle.raccourci).flatMap(RaccourciGlobal.init(rawValue:)))
            ?? RaccourciGlobal.defaut
    }

    /// Remet les valeurs d'origine. Le bouton qui l'appelle existe parce qu'un réglage de
    /// sensation se règle en tâtonnant, et qu'on doit pouvoir revenir au point de départ sans
    /// avoir noté les chiffres.
    public func reinitialiser() {
        modeActivation = .lesDeux
        raccourciGlobal = .defaut
        ancrageZone = .fenetreEncoche
        porteeApproche = Domaine.porteeDefaut
        margeLaterale = Domaine.margeDefaut
        retraitFleches = Domaine.retraitDefaut
        intervalleRafraichissement = Domaine.intervalleDefaut
        delaiRevelation = Domaine.delaiDefaut
        inactiviteFleches = Domaine.inactiviteDefaut
        alignementFleches = alignementFlechesDefaut
        courbeRevelation = courbeRevelationDefaut
        // Les exclusions ne sont PAS remises à zéro : ce n'est pas un réglage de sensation, c'est
        // une liste que l'utilisateur a composée app par app. La perdre par un bouton nommé
        // « valeurs par défaut du geste » serait une surprise.
    }

    public func exclusion(_ bundleID: String, exclue: Bool) {
        if exclue { bundleIDsExclus.insert(bundleID) } else { bundleIDsExclus.remove(bundleID) }
    }

    /// Exclusions qui ne correspondent à aucune des entrées fournies.
    public func exclusionsOrphelines(dans entrees: [EntreeMenu]) -> [String] {
        BouncerCore.exclusionsOrphelines(entrees: entrees, exclus: bundleIDsExclus)
    }

    /// Retire une exclusion.
    public func retirerExclusion(_ bundleID: String) {
        exclusion(bundleID, exclue: false)
    }

    /// Même règle que `borne`, pour une durée. Nommée à part et non surchargée : avec la
    /// conversion implicite CGFloat/Double de Swift, deux surcharges qui ne diffèrent que par ce
    /// type se résolvent au petit bonheur.
    private static func borneDuree(
        _ valeur: TimeInterval?, dans domaine: ClosedRange<TimeInterval>, sinon defaut: TimeInterval
    ) -> TimeInterval {
        guard let valeur, valeur.isFinite else { return defaut }
        return min(max(valeur, domaine.lowerBound), domaine.upperBound)
    }

    private static func borne(_ valeur: CGFloat?, dans domaine: ClosedRange<CGFloat>, sinon defaut: CGFloat) -> CGFloat {
        guard let valeur, valeur.isFinite else { return defaut }
        return min(max(valeur, domaine.lowerBound), domaine.upperBound)
    }
}

/// Les apps que le cycle parcourt vraiment : celles du menu, moins les exclues.
///
/// Fonction pure et séparée de `WindowManager` pour une raison précise : c'est le seul endroit du
/// produit où le menu et le swipe divergent VOLONTAIREMENT, et une divergence voulue doit être
/// lisible et testable, pas planquée dans un `.filter` au milieu d'une propriété calculée.
/// Tout exclure rend la liste vide, donc `cycle()` no-op : c'est cohérent, mais silencieux. La
/// fenêtre de réglages le dit à l'écran plutôt que d'interdire la case — l'utilisateur a le droit
/// de vouloir un menu seul.
public func bundleIDsCyclables(entrees: [EntreeMenu], exclus: Set<String>) -> [String] {
    entrees.map(\.bundleID).filter { !exclus.contains($0) }
}

/// Exclusions enregistrées qui ne correspondent à aucune app détectée dans le menu.
///
/// Une app exclue par le passé qui n'est plus installée ou que le filtre n'accepte plus
/// reste stockée dans les préférences. Cette fonction les isole pour les rendre visibles
/// et retirables dans les réglages.
public func exclusionsOrphelines(entrees: [EntreeMenu], exclus: Set<String>) -> [String] {
    let connus = Set(entrees.map(\.bundleID))
    return exclus.filter { !connus.contains($0) }.sorted()
}

