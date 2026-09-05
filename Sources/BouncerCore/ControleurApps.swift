//
// ControleurApps.swift — toutes les actions de Bouncer sur les apps tierces, derrière un protocole.
//
// Raison d'être : la machine à états de la bascule doit être testable sans lancer ni tuer de
// vraies apps sur la machine de l'utilisateur. Le protocole a donc deux implémentations réelles —
// `ControleurAppsSysteme` ci-dessous et le double des tests — ce qui est exactement ce qui
// distingue une abstraction utile d'une interface à une seule implémentation.
//
// Le code système n'est pas réécrit ici : `masquer` et le recomptage `CGWindowList` sont déplacés
// depuis `WindowManager`, où ils étaient validés au Milestone 0 (cf. SPIKE_RESULTS.md).
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Le protocole

/// Les cinq actions que Bouncer exerce sur une app tierce.
///
/// **Contrat de concurrence** : le protocole est isolé au main actor. Les API sous-jacentes
/// (`NSWorkspace`, `NSRunningApplication`, `AXUIElement`, `CGWindowList`) sont des API AppKit, et
/// l'appelant réel — `WindowManager`, un `ObservableObject` qui publie vers SwiftUI — y vit déjà.
/// Une implémentation n'a donc aucune synchronisation interne à faire, et le double de test peut
/// être une simple classe à état mutable, sans verrou ni `@unchecked Sendable`.
///
/// `lancer` est la seule méthode `async`, parce que `NSWorkspace.openApplication` l'est. Son
/// `await` ne dit PAS que la fenêtre de l'app est à l'écran — seulement que le lancement a été
/// accepté. C'est `fenetreVisibleDansNotch` qu'il faut sonder ensuite.
@MainActor
public protocol ControleurApps {
    /// Lance l'app. `false` si le bundleID n'est installé nulle part, ou si le lancement échoue.
    func lancer(bundleID: String) async -> Bool
    /// Demande la fermeture propre du process. `false` si le pid n'existe plus.
    /// Le `true` dit que la demande est partie, pas que l'app est morte : sonder pour le savoir.
    func tuer(pid: pid_t) -> Bool
    /// Masque (ou réaffiche) l'app via `kAXHiddenAttribute`. Le booléen retourné est un constat
    /// mesuré, pas un code retour d'API : une app qui épingle ses fenêtres dans un Space privé
    /// accepte l'ordre sans rien changer à l'écran, et rend ici `false`.
    ///
    /// `async` parce que le WindowServer ne propage pas l'ordre instantanément et qu'il faut donc
    /// l'attendre : l'attente est une suspension, jamais un blocage du thread principal.
    func masquer(_ masquee: Bool, pid: pid_t) async -> Bool
    /// Vraie mesure : recomptage `CGWindowList` des fenêtres du pid dans la zone de l'encoche.
    /// Ni le code retour de l'API Accessibility ni la relecture de l'attribut ne disent la vérité
    /// (les deux mentent sur boringNotch, cf. SPIKE_RESULTS.md §Étape D) — ne pas les substituer.
    func fenetreVisibleDansNotch(pid: pid_t) -> Bool
    /// pid courant d'un bundleID, `nil` si l'app n'est pas lancée.
    func pid(pour bundleID: String) -> pid_t?
}

// MARK: - Géométrie de l'encoche, partagée

/// Zone de l'encoche en coordonnées AppKit globales (repère de `NSPanel.setFrame` et de
/// `NSEvent.mouseLocation`), avec le nom de l'écran qui la porte. `nil` si aucun écran n'a
/// d'encoche.
///
/// Balaye `NSScreen.screens` et non `NSScreen.main` : `main` est l'écran qui a le focus clavier,
/// pas celui qui porte l'encoche (cf. Spike.swift, cas de l'écran secondaire).
public func zoneEncoche() -> (rect: CGRect, ecran: String, cadre: CGRect)? {
    guard let ecranNotch = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return nil }
    let frame = ecranNotch.frame
    let topInset = ecranNotch.safeAreaInsets.top
    let leftArea = ecranNotch.auxiliaryTopLeftArea ?? .zero
    let rightArea = ecranNotch.auxiliaryTopRightArea ?? .zero
    let notchMinX = leftArea != .zero ? leftArea.maxX : frame.midX - 100
    let notchMaxX = rightArea != .zero ? rightArea.minX : frame.midX + 100
    let notchWidth = max(notchMaxX - notchMinX, 1)
    let rect = CGRect(x: notchMinX, y: frame.maxY - topInset, width: notchWidth, height: topInset)
    // Le cadre de l'écran porteur voyage avec la zone : `estFenetreEncoche` en a besoin pour
    // distinguer un widget d'encoche d'un overlay plein écran, et le redériver ailleurs
    // rouvrirait la porte au hardcoding que CLAUDE.md interdit.
    return (rect, ecranNotch.localizedName, frame)
}

/// Cadre de l'overlay de survol : le boîtier caméra, plus une marge VISIBLE de chaque côté.
///
/// `zoneEncoche()` décrit le boîtier lui-même — tout ce qui sépare `auxiliaryTopLeftArea.maxX` de
/// `auxiliaryTopRightArea.minX`. Cette bande n'est pas affichable : c'est la caméra, pas de l'écran.
/// Mesuré en réel sur le MacBook de référence (écran 1352×878) : aire gauche 0→593, boîtier
/// 593→759, aire droite 759→1352. Une flèche dessinée dans le boîtier est cachée par le matériel,
/// et un curseur qu'on y attend y est invisible — personne ne vise ce qu'il ne voit pas. D'où la
/// marge : les flèches vivent dedans, et la zone sensible (survol, swipe) les englobe.
public func zoneSurvol(encoche: CGRect, marge: CGFloat) -> CGRect {
    encoche.insetBy(dx: -marge, dy: 0)
}

/// Abscisses des deux flèches dans le repère de l'overlay, centrées chacune dans sa marge — donc
/// hors du boîtier caméra par construction, ce que verrouille `ZoneSurvolTests`.
public func abscissesFleches(largeurOverlay: CGFloat, marge: CGFloat, taille: CGFloat)
    -> (gauche: CGFloat, droite: CGFloat)
{
    let decalage = (marge - taille) / 2
    return (decalage, largeurOverlay - marge + decalage)
}

/// Part de l'écran qu'une fenêtre d'encoche ne dépasse pas. Au-delà, c'est un overlay plein écran.
///
/// Relevé sur le MacBook de référence (écran interne 1352 pt de large, boîtier caméra 166 pt) :
/// Vibe Island fait 740 pt (55 % de l'écran) et boringNotch 640 pt (47 %) ; le Dock, la barre de
/// menus du Window Server et l'overlay de capture d'iScreen Shoter font 1352 pt (100 %). Le seuil
/// est posé au milieu de cet écart, et il garde de la marge des deux côtés.
///
/// ponytail: seule constante ajustée du filtre. Une app d'encoche plus large que 80 % de l'écran
/// serait rejetée à tort — si le cas se présente, la mesure à relever est sa largeur réelle.
private let partEcranMaxFenetreEncoche: CGFloat = 0.8

/// Une entrée `CGWindowList` est-elle la fenêtre d'une app d'encoche ?
///
/// Point unique de la conversion de repère : `CGWindowList` a son origine en haut à gauche,
/// AppKit en bas à gauche, et le pivot est la hauteur de `screens[0]` (jamais celle de l'écran
/// courant). Deux appelants s'en servent — le scan de découverte et le recomptage par pid — et
/// ils doivent mesurer exactement la même chose.
///
/// **Pourquoi trois conditions et pas un simple `intersects`.** L'ancien test se contentait de
/// « la fenêtre touche la zone », ce qui laissait entrer n'importe quoi d'assez haut sur l'écran :
/// le catalogue de François avait appris `com.apple.finder`, `com.hnc.Discord`, Arc, iScreen Shoter
/// et Munder Difflin, et son cycle de bascule l'emmenait sur le Finder. Les trois conditions
/// ci-dessous viennent chacune d'un relevé `CGWindowList` réel, jamais d'une intuition :
///
/// 1. **Collée au bord haut.** Les deux vraies ont leur sommet exactement à `cadre.maxY`
///    (écart 0 pt, mesuré sur les deux). Une fenêtre que l'utilisateur déplace, elle, est plafonnée
///    par la barre de menus : Discord et une fenêtre Finder posées le plus haut possible sur
///    l'écran interne s'arrêtent à 35 pt du bord, quand la zone n'en fait que 29. Cette condition
///    à elle seule écarte toute fenêtre de document, plein écran compris.
/// 2. **Elle recouvre le boîtier en entier.** Vibe Island va de 925 à 1665 et boringNotch de 975 à
///    1615, pour un boîtier de 1212 à 1378 : les deux le débordent largement des deux côtés. Ce
///    que ça écarte, ce sont les icônes de barre de menus (`layer` 25, collées au bord haut elles
///    aussi) : relevées entre 26 et 146 pt de large, aucune ne peut contenir un boîtier de 166 pt.
/// 3. **Elle n'occupe pas tout l'écran.** Cf. `partEcranMaxFenetreEncoche`.
///
/// **Ce que ce filtre ne prouve pas.** Aucun des cinq intrus n'a pu être reproduit dans la zone au
/// moment du relevé : leurs fenêtres actuelles sont soit au `layer` 0 (Finder, Arc, Munder
/// Difflin), soit plafonnées à 35 pt du bord (Discord, `layer` 3), soit des icônes de barre de
/// menus (iScreen Shoter). On sait donc que ces trois conditions laissent passer les deux vraies
/// et recalent toutes les fenêtres mesurables sur cette machine ; on ne sait pas laquelle des
/// trois attrapait chacun des cinq intrus le jour où il est entré au catalogue.
func estFenetreEncoche(
    _ zone: CGRect, cadreEcran: CGRect, bounds: [String: CGFloat], hauteurEcranPrincipal: CGFloat
) -> Bool {
    let repereCGWindow = CGRect(
        x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
        width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
    )
    let fenetre = CGRect(
        x: repereCGWindow.origin.x,
        y: hauteurEcranPrincipal - repereCGWindow.origin.y - repereCGWindow.height,
        width: repereCGWindow.width, height: repereCGWindow.height
    )

    // 1 pt de tolérance : le WindowServer rend des bornes déjà entières, mais un facteur d'échelle
    // non entier pourrait en décaler une, et un widget d'encoche à 1 pt du bord reste un widget.
    guard fenetre.maxY >= cadreEcran.maxY - 1 else { return false }
    guard fenetre.minX <= zone.minX, fenetre.maxX >= zone.maxX else { return false }
    guard fenetre.width <= cadreEcran.width * partEcranMaxFenetreEncoche else { return false }
    return true
}

// MARK: - L'implémentation système

/// L'implémentation qui touche vraiment aux apps. Le double des tests implémente le même protocole.
@MainActor
public final class ControleurAppsSysteme: ControleurApps {
    /// `nonisolated` : construire le contrôleur ne touche à rien, et cela permet de s'en servir
    /// comme valeur par défaut d'un paramètre — un argument par défaut est évalué hors isolation.
    public nonisolated init() {}

    /// Ne demande pas l'activation : une app d'encoche est un overlay, lui donner le focus
    /// volerait la fenêtre de premier plan de l'utilisateur pendant la bascule.
    public func lancer(bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    public func tuer(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.terminate()
    }

    /// Déplacé depuis `WindowManager.setHidden` sans changement de logique : le verdict vient du
    /// recomptage des fenêtres du pid avant/après, jamais du retour de
    /// `AXUIElementSetAttributeValue`.
    /// L'attente de propagation du WindowServer : on la sonde au lieu de la subir.
    ///
    /// L'ancien `usleep(300_000)` bloquait le thread principal 300 ms par appel, soit 600 ms de gel
    /// par bascule (deux appels), pour une propagation réelle mesurée entre 1,5 et 31,7 ms
    /// (docs/PERFORMANCE.md §Point 5, et SPIKE_RESULTS.md sur Vibe Island). Le sondage sort dès que
    /// le recomptage constate le changement, et suspend au lieu de bloquer entre deux mesures.
    ///
    /// ponytail: plafond à 100 ms, soit trois fois le pire cas mesuré (31,7 ms sur un `hide`).
    /// Une app plus lente que ça rendra un faux « non régissable » — si ça se produit, la mesure à
    /// relever est le délai réel de propagation sur cette app, pas ce plafond à tâtons.
    private static let plafondPropagation = Duration.milliseconds(100)
    private static let intervalleSondagePropagation = Duration.milliseconds(15)

    public func masquer(_ masquee: Bool, pid: pid_t) async -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        let countBefore = compteFenetres(pid: pid)
        AXUIElementSetAttributeValue(
            appElement, kAXHiddenAttribute as CFString, masquee ? kCFBooleanTrue : kCFBooleanFalse
        )

        // Le sondage attend un changement STRICT du décompte — c'est le seul signe observable que
        // le WindowServer a propagé. Le verdict rendu, lui, reste exactement celui d'avant
        // (`<` au masquage, `>=` à l'affichage) : on remplace l'attente, pas la vérification.
        let echeance = ContinuousClock.now + Self.plafondPropagation
        while ContinuousClock.now < echeance {
            let compte = compteFenetres(pid: pid)
            if masquee ? compte < countBefore : compte > countBefore { break }
            try? await Task.sleep(for: Self.intervalleSondagePropagation)
        }

        let countAfter = compteFenetres(pid: pid)
        return masquee ? countAfter < countBefore : countAfter >= countBefore
    }

    public func fenetreVisibleDansNotch(pid: pid_t) -> Bool {
        guard let (zone, _, cadre) = zoneEncoche() else { return false }
        return compteFenetresDansEncoche(pid: pid, zone: zone, cadreEcran: cadre) > 0
    }

    public func pid(pour bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    // MARK: Recomptage CGWindowList

    /// Toutes les fenêtres à l'écran du pid, où qu'elles soient — c'est la mesure qu'utilise
    /// `masquer`, qui juge un masquage global de l'app.
    private func compteFenetres(pid: pid_t) -> Int {
        fenetres().filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }.count
    }

    /// Les seules fenêtres du pid qui croisent l'encoche, et qui sont des overlays
    /// (`kCGWindowLayer > 0`) : une fenêtre de document normale est au layer 0, y compris en
    /// plein écran, et ne doit pas compter comme une présence dans l'encoche.
    private func compteFenetresDansEncoche(pid: pid_t, zone: CGRect, cadreEcran: CGRect) -> Int {
        guard let hauteurEcran = NSScreen.screens.first?.frame.height else { return 0 }
        return fenetres().filter { entree in
            guard (entree[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let layer = entree[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = entree[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return estFenetreEncoche(
                zone, cadreEcran: cadreEcran, bounds: bounds, hauteurEcranPrincipal: hauteurEcran
            )
        }.count
    }

    private func fenetres() -> [[String: AnyObject]] {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: AnyObject]] ?? []
    }
}
