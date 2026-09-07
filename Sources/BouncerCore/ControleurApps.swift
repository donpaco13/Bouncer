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

/// Hauteur de la rangée de la barre des menus réservée par le système (`frame.maxY - visibleFrame.maxY`).
///
/// Relevé du 2026-09-06 (défaut D1 de la QA passe 4) :
/// Sur un écran à encoche, la rangée réservée par macOS fait 35 pt (34 pt dessinés), alors que le
/// boîtier caméra (`safeAreaInsets.top`) ne fait que 29 pt.
///
/// Interroge en priorité l'écran portant l'encoche, puis `main`, puis le premier écran disponible.
/// Repli de référence : 35 pt (la valeur réservée standard sur MacBook avec encoche).
public func hauteurBarreDesMenus(ecran: NSScreen? = nil) -> CGFloat {
    let s = ecran
        ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        ?? NSScreen.main
        ?? NSScreen.screens.first
    if let s {
        let reserve = s.frame.maxY - s.visibleFrame.maxY
        if reserve > 0 { return reserve }
    }
    return 35
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

/// Bande de référence : le boîtier caméra, plus une marge VISIBLE de chaque côté.
///
/// Ce n'est PLUS le cadre du panel — celui-ci se déduit d'ici en descendant d'une rangée
/// (`bandeFleches`), depuis qu'on a mesuré que la barre des menus n'a aucune portion libre à
/// gauche. Cette bande reste la référence de la zone ÉCOUTÉE (`zoneSwipe`), qui elle a le droit
/// d'y vivre : c'est un test géométrique, pas une fenêtre, donc elle ne recouvre rien.
///
/// `zoneEncoche()` décrit le boîtier lui-même — tout ce qui sépare `auxiliaryTopLeftArea.maxX` de
/// `auxiliaryTopRightArea.minX`. Cette bande n'est pas affichable : c'est la caméra, pas de l'écran.
/// Mesuré en réel sur le MacBook de référence (écran 1352×878) : aire gauche 0→593, boîtier
/// 593→759, aire droite 759→1352. Une flèche dessinée dans le boîtier est cachée par le matériel,
/// et un curseur qu'on y attend y est invisible — personne ne vise ce qu'il ne voit pas. D'où la
/// marge : les flèches vivent dedans, et la zone du swipe (`zoneSwipe`) part de cette bande.
///
/// **Les flèches se calent sur le BOÎTIER, jamais sur la fenêtre de l'app d'encoche**, et c'est
/// une régression corrigée. Calées sur la fenêtre, elles se logeaient aux extrémités d'un panel de
/// 768 pt — c'est-à-dire au beau milieu du bandeau des icônes de statut, qu'elles privaient de
/// leurs clics (le panel vit au niveau `statusBar + 10`, au-dessus d'elles). Relevé CGWindowList
/// du 2026-09-05 : les items de statut occupent les 448 pt les plus à DROITE de la barre des
/// menus (2112→2560 sur l'écran 2560 de la machine ; Hidden Bar, CopyClip, Bouncer, Vorssaint,
/// One Thing, Centre de contrôle). Ramené sur l'écran interne 1352, leur bord gauche tombe à 904
/// quand le boîtier finit à 759 :
///
///   - flèche calée sur le boîtier, marge 64 -> 780→802, soit 102 pt de libre devant le bandeau ;
///   - flèche calée sur la fenêtre, marge 64 -> 1025→1047, soit 118 pt DEDANS, sur Vorssaint.
///
/// La géométrie du swipe, elle, n'a aucune raison de se limiter à cette bande : elle ne recouvre
/// rien, donc elle ne vole rien. C'est tout l'intérêt de les dissocier — un clic doit être précis,
/// un geste peut être large.
///
/// ponytail: la marge est libre parce que les items de statut sont alignés à droite et que macOS
/// les arrête au boîtier. Une barre des menus remplie jusqu'à l'encoche reprendrait ce dégagement.
/// La mesure à relever serait alors le bord gauche réel du bandeau (CGWindowList, `layer` 25).
public func zoneSurvol(encoche: CGRect, marge: CGFloat) -> CGRect {
    encoche.insetBy(dx: -marge, dy: 0)
}

/// Le cadre du PANEL, c'est-à-dire la seule surface où Bouncer prend des clics : la bande de
/// survol, descendue d'une rangée SOUS la barre des menus.
///
/// **Ce que ça corrige, mesuré le 2026-09-06 (relevés `kAXMenuBar`, Arc au premier plan).** Tant
/// que le panel vivait DANS la rangée de la barre des menus, il volait des clics quelle que soit
/// la marge, et des deux côtés :
///
/// ```
/// marge 44  : panel 549→803 · flèche G 560→582 -> Arc « Window » 512→584   CLIC VOLÉ
///                           · flèche D 770→792 -> Arc « Help »   768→819   CLIC VOLÉ
/// marge 96  : panel 497→855 · les deux MÊMES menus volés
/// ```
///
/// Le correctif précédent (T156) n'avait borné que le côté droit, et seulement contre le bandeau
/// des icônes de statut — le seul obstacle qu'il avait mesuré. Or la barre des menus a DEUX
/// occupants, et le premier ne tient pas en place : l'emprise des titres de menus appartient à
/// l'app au premier plan et change avec elle. Relevé le même jour, même écran (1352 pt de large,
/// boîtier 593→759) : Munder Difflin s'arrête à 362, le Finder à 489, Arc à 819 — Arc déborde le
/// boîtier, macOS reprenant la pose de ses titres à droite de la caméra. Le dégagement de gauche
/// va donc de 231 pt à 9 pt selon l'app active, et 9 pt ne logent pas un chevron de 22.
///
/// **Pourquoi une borne en Y et pas deux bornes en X.** Une condition géométrique non bornée est
/// un demi-plan, et ce fichier a déjà cassé trois fois pour avoir été borné d'un seul côté (la
/// zone du geste, la flèche droite, la flèche gauche). Borner en X demanderait de relire
/// `kAXMenuBar` à chaque activation d'app ET à chaque changement de menus DANS une app — une
/// mesure qui se périme entre deux clics, donc un vol de clic à chaque fois qu'elle traîne. La
/// borne en Y n'a pas de côté : la rangée de la barre des menus est le seul endroit où vivent les
/// titres et les icônes de statut, et un panel qui n'y entre pas ne peut rien y prendre, pour
/// n'importe quelle app, sans rien relire.
///
/// Les flèches restent calées sur le BOÎTIER en X — l'acquis de T156, qu'on ne perd pas : posées
/// aux bornes de la fenêtre d'encoche, elles atterrissaient à 118 pt dans le bandeau de statut.
///
/// ponytail: descente de la hauteur réelle de la rangée de la barre des menus (et non de celle du
/// boîtier caméra). Relevé D1 du 2026-09-06 : le boîtier fait 29 pt mais la rangée réserve 35 pt
/// (`NSScreen.frame.maxY - visibleFrame.maxY`). Descendre de 29 pt laissait le panel dans la rangée
/// sur 5 pt et les flèches sur 1,5 pt, privant Arc de clics bas sur « Window » et « Help ».
/// Descendre de la hauteur réservée par le système garantit que le panel et ses contrôles sortent
/// intégralement de la barre des menus.
public func bandeFleches(survol: CGRect, hauteurRangee: CGFloat = hauteurBarreDesMenus()) -> CGRect {
    survol.offsetBy(dx: 0, dy: -hauteurRangee)
}

/// La RANGÉE de la barre des menus au-dessus du boîtier, marges comprises : l'endroit où le
/// curseur fait se déployer l'app d'encoche tierce.
///
/// Ce n'est pas tout à fait `zoneSurvol`. Celle-ci part du boîtier caméra, qui fait 29 pt, quand
/// la rangée que macOS réserve en fait 35 (relevé D1 du 2026-09-06, cf. `hauteurBarreDesMenus`).
/// Les 6 pt d'écart tombaient entre les deux bandes : ni « sur l'encoche », ni « sur les flèches ».
/// Un curseur qui monte du chevron vers l'encoche les traverse à chaque fois, et une frontière
/// qu'on traverse est une frontière qui clignote.
public func bandeEncoche(survol: CGRect, hauteurRangee: CGFloat = hauteurBarreDesMenus()) -> CGRect {
    let hauteur = max(survol.height, hauteurRangee)
    return CGRect(x: survol.minX, y: survol.maxY - hauteur, width: survol.width, height: hauteur)
}

/// L'app d'encoche occupe-t-elle la place, au point que les flèches n'aient plus rien à y faire ?
///
/// **Le défaut, dans ses mots** (2026-09-07) : « quand on est sur le notch les flèches restent
/// visibles alors que l'application du notch est ouverte, donc c'est pas propre propre ». Les
/// chevrons vivent une rangée SOUS la barre des menus (`bandeFleches`) et le panel monte au niveau
/// `statusBar + 10` : quand l'app tierce déploie son panneau, ils sont dessinés PAR-DESSUS. Et ils
/// y étaient à pleine opacité, la portée d'approche (72 pt) couvrant très largement les 6 pt qui
/// séparent la rangée de la barre des menus de la leur.
///
/// **Quand exactement, et pourquoi ce signal-là.** Trois candidats se présentaient :
///
///   1. *La fenêtre a grandi au-delà de la bande.* Écarté, et c'est mesuré : les conteneurs des
///      apps d'encoche NE BOUGENT PAS au déploiement (relevé du 2026-09-05, cf.
///      `WindowManager.cadreFenetresEncoche` — boringNotch 640×210, Vibe Island 740×520, fixes,
///      transparents). Il n'y a pas de croissance à observer.
///   2. *Le curseur est entré dans la surface de la fenêtre.* Écarté aussi, et c'est le piège :
///      cette surface couvre la bande des flèches elle-même, donc les chevrons s'effaceraient
///      exactement au moment où l'on va les cliquer. Ça ne corrige pas un défaut, ça en crée un.
///   3. *Le curseur est sur l'encoche.* Retenu. C'est le geste qui fait se déployer l'app tierce —
///      c'est même sa seule commande —, et c'est littéralement ce que dit le rapport : « quand on
///      est sur le NOTCH ». La bande est une rangée AU-DESSUS de celle des chevrons : une main qui
///      descend vers un chevron n'y entre jamais, une main qui monte vers l'encoche y entre
///      toujours. Le bouton est intact, la révélation graduelle aussi.
///
/// La seconde condition n'est pas décorative : sans recouvrement réel, il n'y a rien de sale à
/// corriger, et effacer les flèches ne serait qu'une perte. C'est la même règle que la pastille de
/// contraste (`flechesPoseesSurUneAppTierce`) — c'est la géométrie qui décide, pas le réglage.
///
/// ponytail: le signal est le curseur, pas l'état réel de l'app tierce, qui ne se publie nulle
/// part. Une app d'encoche qui resterait déployée après que le curseur en est sorti (épinglage,
/// lecture en cours) laisserait les flèches revenir par-dessus. La mesure à relever serait alors
/// la région DESSINÉE de sa fenêtre (`CGWindowListCreateImage` sur le cadre du chevron), au prix
/// d'une capture d'écran par approche et de l'autorisation qui va avec.
public func encocheOccupee(
    curseur: CGPoint, bandeEncoche: CGRect, cadreFleches: CGRect, fenetre: CGRect?
) -> Bool {
    guard let fenetre, !fenetre.isEmpty, fenetre.intersects(cadreFleches) else { return false }
    return bandeEncoche.contains(curseur)
}

/// Ce que Bouncer ÉCOUTE : la bande des flèches, détendue de 6 pt en haut et en bas (elle fait
/// ~29 pt, difficile à survoler pile), réunie à la fenêtre d'encoche mais BORNÉE en hauteur.
///
/// Contrairement à la bande des flèches, cette zone n'est pas une fenêtre : c'est un test
/// géométrique, elle peut donc s'étendre bien au-delà du boîtier sans rien recouvrir. C'est ce qui
/// rattrape le geste que l'utilisateur pose sur l'île qu'il VOIT — mesuré le 2026-09-05 : un geste
/// à 180 pt à droite de l'ancienne bande tombait 13 fois par le garde `horsZone`, un geste posé
/// 80 pt sous la barre des menus ne laissait aucune trace, le monitor n'étant même pas attaché.
/// La LARGEUR suit donc la fenêtre, sans réserve : c'est elle qui rend le geste trouvable, et un
/// défilement horizontal à hauteur de barre des menus n'existe pratiquement pas.
///
/// La HAUTEUR, elle, est plafonnée, et c'est une régression corrigée. Prendre la fenêtre entière
/// portait la zone à 38,5 % de l'écran interne avec Vibe Island (868×526 sur 1352×878), où un
/// défilement horizontal ORDINAIRE suffisait à basculer l'encoche — rejeu mesuré : 40 événements
/// de −12 pt en X, soit 480 pt continus, une bascule. Et le garde qui devait tenir ce faux positif
/// (la dominance horizontale du `DetecteurSwipe`) ne peut rien : un défilement de carrousel EST
/// horizontal.
///
/// La fenêtre d'une app d'encoche n'est pas son île. Relevé CGWindowList du 2026-09-05 :
/// TheBoringNotch publie un canevas de 640×210 et Vibe Island un de 740×520, quand l'île fermée
/// en fait quelques dizaines de points ; capture de la région exacte du canevas de boringNotch —
/// 640×210 — pas un pixel dessiné, luminance uniforme du fond d'écran sur les 210 pt. Écouter la
/// fenêtre entière revenait à écouter un canevas transparent.
///
/// Le plafond est posé sur le geste le plus BAS réellement mesuré, pas au jugé : cf.
/// `descenteMaxZoneSwipe`.
public func zoneSwipe(bande: CGRect, fenetre: CGRect?) -> CGRect {
    // La bande des flèches est comprise sans condition : depuis qu'elle est descendue d'une
    // rangée (`bandeFleches`), un curseur qui va CHERCHER une flèche sort de la rangée de la
    // barre des menus. S'il sortait du même coup de la zone écoutée, le panel se retirerait sous
    // la main — et en mode « boîtier seul », où `fenetre` vaut nil, il n'y aurait rien d'autre
    // pour rattraper la descente.
    let base = bande.union(bandeFleches(survol: bande)).insetBy(dx: 0, dy: -6)
    guard let fenetre, !fenetre.isEmpty else { return base }
    let elargi = base.union(fenetre)
    // Le plafond se mesure depuis la RANGÉE de la barre des menus, pas depuis le bas de `base` :
    // c'est de là que partait le relevé des 120 pt, et l'ancrer sur `base` ferait descendre la
    // zone d'une rangée de plus à chaque fois qu'on descend les flèches.
    let plancher = bande.minY - descenteMaxZoneSwipe
    guard elargi.minY < plancher else { return elargi }
    return CGRect(x: elargi.minX, y: plancher, width: elargi.width, height: elargi.maxY - plancher)
}

/// De combien de points la zone écoutée descend SOUS la bande des flèches, au plus.
///
/// 120, et le chiffre vient d'un relevé : le geste le plus bas que François ait réellement posé et
/// que Bouncer ait raté était à 80 pt sous la barre des menus (mesure du 2026-09-05, celle qui a
/// motivé l'élargissement). 120 le couvre avec 50 % de réserve, et laisse la zone à ~155 pt sous
/// le bord haut de l'écran une fois la bande et sa détente comptées.
///
/// Ce que ça donne sur la machine de référence (écran interne 1352×878) : Vibe Island passe de
/// 868×526 = 38,5 % à 740×155 = 9,7 %, boringNotch de 768×216 = 14,0 % à 640×155 = 8,4 %. Le
/// plafond absolu est celui de `partEcranMaxFenetreEncoche` (80 % de large) × 155 pt de haut.
///
/// ponytail: plafond en points, pas en fraction d'île. Une app dont l'île fermée descendrait plus
/// bas que 120 pt perdrait le geste posé sur son bord bas — la mesure à relever serait alors la
/// hauteur DESSINÉE de cette île, pas celle de son canevas.
private let descenteMaxZoneSwipe: CGFloat = 120

/// Côté du chevron dessiné dans une bande de `hauteurBande` points.
///
/// 22 pt et non 14 : une cible de clic de 14 pt dans une marge de 44 était petite pour rien, et la
/// pastille — quand elle est nécessaire — doit rester lisible sur une pochette d'album. Les 4 pt
/// retirés sont la respiration au-dessus et en dessous : la bande fait 29 pt sur la machine de
/// référence, le chevron 22, il reste 3,5 pt de chaque côté.
public func tailleFleche(hauteurBande: CGFloat) -> CGFloat {
    min(hauteurBande - 4, 22)
}

/// Les deux cadres des flèches dans le repère de l'overlay : chacune centrée dans sa marge, et
/// centrée en hauteur dans la bande.
///
/// Ce calcul vivait dans `NotchArrowsView.layoutArrows`, donc nulle part où un test puisse le
/// regarder. Il en est sorti le jour où les chevrons se sont retrouvés à moitié coupés à l'écran
/// (cf. `ancreAuCentre`) : la géométrie était juste, le DESSIN ne l'était pas, et aucun test ne
/// pouvait le dire tant que rien de tout ça ne franchissait les bornes de la vue.
public func cadresFleches(
    overlay: CGSize, marge: CGFloat, alignement: CGFloat = alignementFlechesDefaut
) -> (gauche: CGRect, droite: CGRect) {
    let taille = tailleFleche(hauteurBande: overlay.height)
    let y = (overlay.height - taille) / 2
    let x = abscissesFleches(
        largeurOverlay: overlay.width, marge: marge, taille: taille, alignement: alignement
    )
    return (
        CGRect(x: x.gauche, y: y, width: taille, height: taille),
        CGRect(x: x.droite, y: y, width: taille, height: taille)
    )
}

/// Centre le point d'ancrage du calque d'une vue AppKit SANS le déplacer.
///
/// Une échelle de révélation doit grandir autour du centre du chevron, sinon il se déploie vers le
/// coin haut-droit. Le réflexe est de poser `anchorPoint = (0.5, 0.5)` sur le calque, et c'est
/// exactement ce qui coupait les flèches en deux — constaté en réel le 2026-09-06 : « les flèches
/// sont à moitié coupées, on dirait qu'il y a une limite et qu'on ne peut pas afficher des
/// éléments en dessous de cette hauteur ».
///
/// AppKit tient le calque d'une vue avec `anchorPoint = (0, 0)` et `position = frame.origin`, et
/// il ne recalcule PAS `position` quand on déplace l'ancre — ni au moment du changement, ni à la
/// pose suivante du cadre. MESURÉ : un bouton de 22×22 posé à (11 ; 3,5) dans une bande de 29 pt
/// garde `position = (11 ; 3,5)` et se retrouve DESSINÉ à (0 ; −7,5), décalé d'une demi-taille
/// vers le bas et vers la gauche. Ses 7,5 pt du bas tombent sous le bord du panel, qui ne fait que
/// la hauteur du boîtier : ils sont écrêtés par la fenêtre, sans erreur ni log.
///
/// La vue, elle, n'avait pas bougé d'un point : `hitTest` répondait toujours au bon endroit, ce
/// qui explique que ni un test de géométrie ni un relevé de cadre n'aient pu le voir. Recaler
/// `position` sur le centre du cadre remet le dessin là où la vue l'annonce, et ne touche à AUCUNE
/// cible de clic.
@MainActor public func ancreAuCentre(_ calque: CALayer, cadreVue: CGRect) {
    calque.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    calque.position = CGPoint(x: cadreVue.midX, y: cadreVue.midY)
}

/// Abscisses des deux flèches dans le repère de l'overlay, centrées chacune dans sa marge — donc
/// hors du boîtier caméra ET hors de la fenêtre d'encoche par construction, ce que verrouille
/// `ZoneSurvolTests`.
/// Où le chevron se pose DANS sa marge. 0 = collé au boîtier caméra, 1 = au bord extérieur,
/// 0,5 = centré, et c'est ce que le produit fait depuis toujours.
///
/// Exposé parce que c'est un parti pris de forme, pas une mesure : « épouser le contour de
/// l'encoche » et « flotter à côté d'elle » sont deux réponses défendables à la même question, et
/// elle n'est pas tranchée. Cf. `docs/rapport-fleches-propres.html`, piste P3.
public let alignementFlechesDefaut: CGFloat = 0.5

public func abscissesFleches(
    largeurOverlay: CGFloat, marge: CGFloat, taille: CGFloat,
    alignement: CGFloat = alignementFlechesDefaut
) -> (gauche: CGFloat, droite: CGFloat)
{
    // L'alignement est SYMÉTRIQUE, donc lu à l'envers d'un côté : « collé au boîtier » veut dire
    // au bord DROIT de la marge gauche, et au bord GAUCHE de la marge droite. Une seule valeur
    // pour les deux côtés, sans quoi régler l'un désalignerait l'autre.
    let a = min(max(alignement, 0), 1)
    let course = marge - taille
    return (course * (1 - a), largeurOverlay - marge + course * a)
}

/// Part de l'écran qu'une fenêtre d'encoche ne dépasse pas. Au-delà, c'est un overlay plein écran.
///
/// Relevé sur le MacBook de référence (écran interne 1352 pt de large, boîtier caméra 166 pt) :
/// Vibe Island fait 740 pt (55 % de l'écran) et boringNotch 640 pt (47 %) ; le Dock, la barre de
/// menus du Window Server et l'overlay de capture d'iScreen Shoter font 1352 pt (100 %). Le seuil
/// est posé au milieu de cet écart, et il garde de la marge des deux côtés.
///
/// **Le cas annoncé s'est présenté, et le seuil ne bouge pas pour autant** (campagne du
/// 5 septembre 2026, `docs/COMPATIBILITE.md` §3.2). NotchNook, Notchy et Mew Notch dessinent leur
/// encoche dans un calque de 1352 pt sur un écran de 1352 pt : exactement le profil du Dock, de la
/// barre de menus du Window Server et de l'overlay de capture. Aucune mesure `CGWindowList` ne les
/// en sépare — ni la largeur, ni le sommet, ni le recouvrement du boîtier, et la hauteur n'entre
/// dans aucune des trois conditions. Relever le plafond pour les faire entrer réadmettrait les
/// trois autres AU CATALOGUE, c'est-à-dire referait le cycle de bascule qui emmenait sur le Finder.
///
/// Ces trois apps sont donc régies par leur bundleID (`appsEncocheConnues`), jamais par la
/// découverte géométrique — symétrique exact de l'exclusion de Bouncer elle-même, dont l'overlay
/// EST une fenêtre d'encoche au sens de ce filtre. Cf. `couvreEncoche`.
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
///
/// **Deux questions, deux prédicats, et c'est ce qui gagne trois apps sans rien relâcher.** Celui-ci
/// répond à « cette fenêtre INCONNUE est-elle une app d'encoche ? » — il alimente la découverte,
/// donc le catalogue, donc le cycle de bascule, et la moindre indulgence s'y paie en faux positifs
/// définitifs. `couvreEncoche` répond à l'autre question, « l'app que je viens de nommer par son
/// bundleID couvre-t-elle l'encoche ? », et elle n'a pas besoin du plafond de largeur : sur un pid
/// choisi, il n'y a plus rien à départager d'avec le Dock.
func estFenetreEncoche(
    _ zone: CGRect, cadreEcran: CGRect, bounds: [String: CGFloat], hauteurEcranPrincipal: CGFloat
) -> Bool {
    cadreFenetreEncoche(zone, cadreEcran: cadreEcran, bounds: bounds,
                        hauteurEcranPrincipal: hauteurEcranPrincipal) != nil
}

/// L'app désignée par ce pid couvre-t-elle l'encoche ? Les conditions 1 et 2, sans la 3.
///
/// **Pourquoi le plafond de largeur saute ICI et nulle part ailleurs.** Il existe pour départager
/// un inconnu d'un overlay plein écran, et il ne sait le faire qu'en refusant les deux. Quand
/// l'appelant tient déjà le pid d'une app de son catalogue — `fenetreVisibleDansNotch`, son seul
/// appelant — l'inconnu n'existe plus : la question n'est pas « qui est-ce », c'est « sa surface
/// est-elle à l'écran ». Rien n'est appris par ce chemin (`catalogue.apprendre` ne se lit que dans
/// le scan de découverte), donc aucun faux positif ne peut en sortir, et NotchNook, Notchy et Mew
/// Notch redeviennent mesurables alors que leur calque de 1352 pt reste inconnu du scan.
///
/// Le catalogue garde donc ses deux portes d'entrée, et les deux restent gardées : la découverte
/// par la géométrie stricte, l'amorçage par des bundleIDs relevés dans un `Info.plist`.
func couvreEncoche(
    _ zone: CGRect, cadreEcran: CGRect, bounds: [String: CGFloat], hauteurEcranPrincipal: CGFloat
) -> Bool {
    cadreCouvrantLeBoitier(zone, cadreEcran: cadreEcran, bounds: bounds,
                           hauteurEcranPrincipal: hauteurEcranPrincipal) != nil
}

/// Le même prédicat, mais qui REND le cadre converti en repère AppKit plutôt qu'un booléen : la
/// géométrie des flèches et de la zone de swipe se cale dessus (`zoneSwipe`), et
/// la relire une seconde fois ailleurs rouvrirait la porte aux deux conversions divergentes que
/// ce fichier existe pour empêcher.
func cadreFenetreEncoche(
    _ zone: CGRect, cadreEcran: CGRect, bounds: [String: CGFloat], hauteurEcranPrincipal: CGFloat
) -> CGRect? {
    guard let fenetre = cadreCouvrantLeBoitier(
        zone, cadreEcran: cadreEcran, bounds: bounds, hauteurEcranPrincipal: hauteurEcranPrincipal
    ) else { return nil }
    guard fenetre.width <= cadreEcran.width * partEcranMaxFenetreEncoche else { return nil }
    return fenetre
}

/// Les conditions 1 et 2 seules, et le point unique de la conversion de repère.
///
/// Ni l'une ni l'autre ne lit la hauteur de la fenêtre : elle s'annule dans la conversion
/// (`maxY = hauteurEcranPrincipal - Y`, où `Y` est le sommet du repère CGWindow). C'est ce qui
/// permet de tester les trois apps de 1352 pt avec la seule mesure que la campagne ait relevée
/// sur elles — leur largeur.
private func cadreCouvrantLeBoitier(
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
            // La porte unique de `dormirSondage`, et pas un `try?` nu : celui-ci rendait la main
            // sur-le-champ sur une tâche annulée, et les ~7 tours restants devenaient 100 ms de
            // boucle serrée sur le main actor. Cette boucle-là n'avait jamais vu de tâche
            // annulable — jusqu'à ce que `Bascule.poursuivreFermeture(puisEteindre:)` en fasse
            // passer une par `eteindre` (QA passe 6, §3). Sortir sans avoir vu le changement rend
            // le même verdict qu'un plafond atteint : le recomptage qui suit tranche.
            guard await dormirSondage(Self.intervalleSondagePropagation) else { break }
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
    ///
    /// `couvreEncoche` et non `estFenetreEncoche` : le pid vient du catalogue, l'app est déjà
    /// identifiée, et le plafond de largeur n'a plus rien à y départager — il ne ferait que rendre
    /// invisibles les apps d'encoche qui dessinent sur toute la largeur (cf. sa doc).
    private func compteFenetresDansEncoche(pid: pid_t, zone: CGRect, cadreEcran: CGRect) -> Int {
        guard let hauteurEcran = NSScreen.screens.first?.frame.height else { return 0 }
        return fenetres().filter { entree in
            guard (entree[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let layer = entree[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = entree[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return couvreEncoche(
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
