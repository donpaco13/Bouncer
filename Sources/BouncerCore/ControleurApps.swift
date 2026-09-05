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
    /// Lève le masquage sans rien mesurer ni attendre la propagation du WindowServer.
    ///
    /// C'est le seul geste possible depuis un handler de terminaison — l'app est en train de
    /// mourir, il n'y a plus de tour de run loop pour sonder quoi que ce soit — et c'est aussi
    /// tout ce dont on a besoin au démarrage, où l'on ignore ce qu'une session précédente a
    /// laissé masqué et où le verdict ne servirait à rien. Sans valeur de retour, donc :
    /// l'appelant n'a rien à en faire, et prétendre mesurer serait mentir.
    func reafficherSansAttendre(pid: pid_t)
}

// MARK: - Le trust Accessibilité, et pourquoi c'est une latche

/// Vrai dès que ce process a obtenu le droit Accessibilité au moins une fois depuis son lancement.
///
/// **Ce n'est pas `AXIsProcessTrusted()`, et la nuance commande tout le garde-fou de la bascule.**
/// Constaté en test réel (cf. le commentaire de `WindowManager.refresh`) : un appel
/// `AXUIElementSetAttributeValue` fait par ce process AVANT le premier octroi laisse sa connexion
/// Accessibility hors service pour le reste de sa vie — même après que `AXIsProcessTrusted()`
/// repasse à true, il faut relancer Bouncer. Les appels faits APRÈS un octroi puis un retrait,
/// eux, échouent sans rien condamner : la connexion a été établie une fois pour toutes. C'est ce
/// qui autorise le repli par cycle de vie à ramener une app restée masquée quand l'utilisateur
/// décoche Bouncer en cours de route (`RobustesseTests`) — comportement qu'un garde posé sur
/// `AXIsProcessTrusted()` seul supprimerait, en laissant l'app introuvable.
///
/// La latche n'est jamais remise à false : le droit peut être retiré, le fait qu'il ait été
/// accordé une fois, non — et c'est ce fait-là, pas l'état courant, qui dit si l'API AX est sûre
/// à toucher.
@MainActor private var trustDejaAccorde = false

@MainActor public func accessibiliteDejaAccordee() -> Bool {
    if !trustDejaAccorde, AXIsProcessTrusted() { trustDejaAccorde = true }
    return trustDejaAccorde
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

/// Le boîtier caméra tel qu'on le DESSINE, quand on ne peut pas dessiner le vrai.
///
/// Les aperçus (`ApercuGeste` dans les réglages, `SimulateurNotchInteractif` dans le guide) figurent
/// une encoche à une échelle qui n'est pas celle de l'écran : ils ont besoin de ses PROPORTIONS, pas
/// de ses points. Interroger l'écran plutôt que réécrire un chiffre, c'est la règle « zéro
/// hardcoding d'encoche » du CLAUDE.md — deux vues l'avaient enfreinte chacune de son côté, l'une
/// avec 166 pt et l'autre avec 130, pour le même objet.
///
/// Le repli n'est pas une devinette : c'est le relevé de la machine de référence (166×29, cf.
/// `ZoneSurvolTests`). Il ne sert que sur un Mac sans encoche, où il n'y a rien à interroger et où
/// l'aperçu doit tout de même montrer quelque chose de juste.
public var boitierEncocheReference: CGSize {
    zoneEncoche()?.rect.size ?? CGSize(width: 166, height: 29)
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

/// Cadre de l'overlay quand il se cale sur LA FENÊTRE réellement posée sur l'encoche.
///
/// MESURÉ le 2026-09-05, et c'est la cause racine des swipes ratés : la bande que Bouncer écoutait
/// faisait 254×41 pt (boîtier 166 + 2×44 de marge), quand la fenêtre que l'utilisateur VOIT et
/// vise fait 640×210 pt (boringNotch) ou 740×520 pt (Vibe Island). Un geste posé sur l'île, à
/// 180 pt à droite de la bande, était rejeté 13 fois de suite par le garde `horsZone` ; un geste
/// posé 80 pt sous la barre des menus ne laissait AUCUNE trace, le monitor n'étant même pas
/// attaché. Viser ce qu'on voit ne marchait que sur 2,7 % de la surface visible.
///
/// La largeur suit donc la fenêtre, plus `marge` de chaque côté pour y loger les flèches — qui se
/// retrouvent ainsi HORS de la surface de l'app tierce, ce qui règle du même coup le contraste
/// (cf. `NotchArrowsView`). La HAUTEUR, elle, reste celle de la barre des menus : le panel est une
/// vraie fenêtre au niveau 35, et lui donner les 520 pt de Vibe Island la ferait recouvrir un tiers
/// de l'écran pour n'y dessiner que deux chevrons.
///
/// `ecran` borne le tout : une fenêtre d'encoche large sur un écran étroit pousserait les flèches
/// hors champ.
public func cadreFleches(encoche: CGRect, marge: CGFloat, fenetre: CGRect?, ecran: CGRect) -> CGRect {
    let base = zoneSurvol(encoche: encoche, marge: marge)
    guard let fenetre, !fenetre.isEmpty else { return base }
    let elargi = CGRect(x: fenetre.minX - marge, y: base.minY,
                        width: fenetre.width + 2 * marge, height: base.height)
    return base.union(elargi).intersection(
        CGRect(x: ecran.minX, y: base.minY, width: ecran.width, height: base.height)
    )
}

/// Ce que Bouncer ÉCOUTE : le cadre des flèches, détendu de 6 pt en haut et en bas (la bande fait
/// ~29 pt, difficile à survoler pile), réuni à la fenêtre d'encoche en entier.
///
/// Contrairement au cadre des flèches, cette zone n'est pas une fenêtre : c'est un test
/// géométrique. Elle peut donc prendre toute la hauteur de l'île sans rien recouvrir, et c'est ce
/// qui rattrape le geste posé sous la barre des menus. Le faux positif que ça ouvrirait — un
/// défilement horizontal fait par mégarde dans cette région — est écarté ailleurs, par la
/// dominance horizontale du `DetecteurSwipe` : un défilement vertical qui dérive n'y suffit pas.
public func zoneSwipe(cadreFleches: CGRect, fenetre: CGRect?) -> CGRect {
    let bande = cadreFleches.insetBy(dx: 0, dy: -6)
    guard let fenetre, !fenetre.isEmpty else { return bande }
    return bande.union(fenetre)
}

/// Abscisses des deux flèches dans le repère de l'overlay, centrées chacune dans sa marge — donc
/// hors du boîtier caméra ET hors de la fenêtre d'encoche par construction, ce que verrouille
/// `ZoneSurvolTests`.
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
/// 1. **Sommet AU bord haut de l'écran porteur**, à 1 pt près des deux côtés. Les deux vraies ont
///    leur sommet exactement à `cadre.maxY` (écart 0 pt, mesuré sur les deux). Une fenêtre que
///    l'utilisateur déplace, elle, est plafonnée par la barre de menus : Discord et une fenêtre
///    Finder posées le plus haut possible sur l'écran interne s'arrêtent à 35 pt du bord, quand la
///    zone n'en fait que 29. Cette condition à elle seule écarte toute fenêtre de document, plein
///    écran compris — et, depuis qu'elle est bornée des deux côtés, tout ce qui vit sur un autre
///    écran (cf. le paragraphe suivant).
/// 2. **Elle recouvre le boîtier en entier.** Vibe Island va de 925 à 1665 et boringNotch de 975 à
///    1615, pour un boîtier de 1212 à 1378 : les deux le débordent largement des deux côtés. Ce
///    que ça écarte, ce sont les icônes de barre de menus (`layer` 25, collées au bord haut elles
///    aussi) : relevées entre 26 et 146 pt de large, aucune ne peut contenir un boîtier de 166 pt.
/// 3. **Elle n'occupe pas tout l'écran.** Cf. `partEcranMaxFenetreEncoche`.
///
/// **La fuite inter-écrans, mesurée le 5 septembre 2026.** L'auteur du filtre avait écrit qu'il
/// n'avait pas pu le confronter à de vrais intrus. C'est arrivé : `com.pais.handy` et
/// `com.apple.UserNotificationCenter` sont entrés au catalogue. Relevé sur la machine de référence
/// (interne 1352×878 à `y ∈ [-878, 0]`, externe 2560×1415 à `y ∈ [0, 1415]`) : la pastille de
/// Handy, posée en haut de l'écran EXTERNE, mesure `X:1152→1408, maxY = 61`. Elle passait les trois
/// conditions — `maxY = 61 ≥ cadre.maxY - 1 = -1`, elle englobe le boîtier `1212→1378` par simple
/// recouvrement d'abscisses entre deux écrans, et 256 pt tiennent sous le plafond de largeur.
///
/// Aucune des trois ne disait « sur l'écran qui porte l'encoche » : la condition 1, en `≥` seul,
/// était satisfaite d'office par tout écran situé plus haut dans le repère AppKit. La borner des
/// deux côtés suffit, et c'est la formulation exacte de ce qui avait été mesuré dès le départ
/// (sommet À `cadre.maxY`, pas au-dessus). Les alertes de `UserNotificationCenter`, centrées sur
/// l'écran externe donc à cheval sur les abscisses du boîtier, relevaient de la même fuite.
func estFenetreEncoche(
    _ zone: CGRect, cadreEcran: CGRect, bounds: [String: CGFloat], hauteurEcranPrincipal: CGFloat
) -> Bool {
    cadreFenetreEncoche(zone, cadreEcran: cadreEcran, bounds: bounds,
                        hauteurEcranPrincipal: hauteurEcranPrincipal) != nil
}

/// Le même prédicat, mais qui REND le cadre converti en repère AppKit plutôt qu'un booléen : la
/// géométrie des flèches et de la zone de swipe se cale dessus (`cadreFleches`, `zoneSwipe`), et
/// la relire une seconde fois ailleurs rouvrirait la porte aux deux conversions divergentes que
/// ce fichier existe pour empêcher.
func cadreFenetreEncoche(
    _ zone: CGRect, cadreEcran: CGRect, bounds: [String: CGFloat], hauteurEcranPrincipal: CGFloat
) -> CGRect? {
    let repereCGWindow = CGRect(
        x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
        width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
    )
    let fenetre = CGRect(
        x: repereCGWindow.origin.x,
        y: hauteurEcranPrincipal - repereCGWindow.origin.y - repereCGWindow.height,
        width: repereCGWindow.width, height: repereCGWindow.height
    )

    // Encadrée des DEUX côtés, et c'est le tout du correctif de la fuite inter-écrans : en `≥`
    // seul, la condition ne disait rien qu'une fenêtre d'un écran plus haut ne satisfasse
    // gratuitement. 1 pt de tolérance : le WindowServer rend des bornes déjà entières, mais un
    // facteur d'échelle non entier pourrait en décaler une, et un widget d'encoche à 1 pt du bord
    // reste un widget.
    guard abs(fenetre.maxY - cadreEcran.maxY) <= 1 else { return nil }
    guard fenetre.minX <= zone.minX, fenetre.maxX >= zone.maxX else { return nil }
    guard fenetre.width <= cadreEcran.width * partEcranMaxFenetreEncoche else { return nil }
    return fenetre
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

    public func reafficherSansAttendre(pid: pid_t) {
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid), kAXHiddenAttribute as CFString, kCFBooleanFalse
        )
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
