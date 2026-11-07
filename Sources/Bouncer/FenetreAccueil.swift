//
// FenetreAccueil.swift — le premier contact avec Bouncer.
//
// Bouncer est un utilitaire d'arrière-plan sans icône dans le Dock (`LSUIElement = true`) : au
// premier lancement, rien à l'écran ne dit qu'il existe, ni ce qu'il fait, ni ce qu'il attend.
// Cette fenêtre est donc le seul endroit où l'app se présente, et elle le fait en cinq écrans
// (`EtapeAccueil`, BouncerCore) : bienvenue, le problème, l'autorisation, le geste, l'état.
//
// Parti pris visuel : fond sombre plein cadre, aucun chrome sauf les pastilles de fenêtre, et le
// mot « hello » qui S'ÉCRIT à l'ouverture — le tracé de `TraceHello` est un chemin de Bézier
// unique, révélé par `trim(from:to:)` animé de 0 à 1, comme au premier démarrage d'un Mac. Ce
// n'est pas une police cursive posée là : une police se contenterait d'apparaître.
//
// Contraintes architecturales :
//   - NSWindow classique (pas de NSPanel non-activating) pour accepter le focus et les clics.
//   - Apparence forcée en `.darkAqua` : les pastilles de fenêtre et toutes les couleurs
//     sémantiques (`.secondary`, `.windowBackgroundColor` des sous-vues réutilisées) doivent se
//     résoudre en sombre quel que soit le thème du système, sinon les composants repris du guide
//     précédent peignent du gris clair sur le dégradé bleu nuit.
//   - Hauteur plafonnée à ce que l'écran offre (`hauteurContenu`) avec `ScrollView` : MESURÉ le
//     2026-09-05 sur l'écran interne d'un MacBook (`visibleFrame.height` = 780 pt). Sur un écran court
//     ou avec un Dock agrandi, le contenu défile et les boutons du pied de page restent ancrés et
//     atteignables en permanence.
//   - Aucun appel d'API AX direct : on lit uniquement l'état publié par WindowManager /
//     EtatAccueil (un appel AX passé avant l'octroi du trust condamne la connexion du process).
//   - Réactivité native : l'écran de l'Accessibilité passe au vert tout seul dès que
//     l'utilisateur coche Bouncer dans les Réglages, sans relancer ni recliquer.
//

import AppKit
import BouncerCore
import Combine
import SwiftUI

// MARK: - Contrôleur de fenêtre

/// Sous-classe de NSWindow qui intercepte Échap (`cancelOperation`) pour fermer la fenêtre
/// proprement, indispensable dans une application d'arrière-plan (LSUIElement) sans menu Fichier.
///
/// SEUL point d'interception d'Échap pour cette fenêtre. La chaîne des répondeurs y aboutit quel
/// que soit l'endroit où le focus se trouve dans le contenu SwiftUI, ce qu'un bouton invisible
/// portant `.keyboardShortcut(.cancelAction)` ne garantit pas.
private final class FenetreAccueilWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

@MainActor
final class FenetreAccueilController: NSObject, NSWindowDelegate {
    private static let cleVue = "bouncer.accueilVu"

    /// Taille du parcours. Fixe d'un écran à l'autre : une fenêtre qui grandit et rétrécit à
    /// chaque « Continuer » donne l'impression que le contenu saute, et déplace le bouton sous le
    /// curseur entre deux clics.
    private static let largeur: CGFloat = 660
    private static let hauteurVoulue: CGFloat = 580

    private let windowManager: WindowManager
    private let defaults: UserDefaults
    private var fenetre: NSWindow?

    init(windowManager: WindowManager, defaults: UserDefaults = .standard) {
        self.windowManager = windowManager
        self.defaults = defaults
        super.init()
    }

    /// Affiche le parcours uniquement si l'utilisateur ne l'a pas encore refermé une première fois.
    func afficherSiPremierLancement() {
        guard !defaults.bool(forKey: Self.cleVue) else { return }
        afficher()
    }

    /// Ouvre ou ramène la fenêtre au premier plan (déclenché aussi depuis le menu de l'app).
    func afficher() {
        if let fenetre {
            fenetre.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hote = NSHostingController(
            rootView: VueAccueil(
                windowManager: windowManager,
                reglages: windowManager.reglages,
                largeur: Self.largeur,
                hauteur: Self.hauteurContenu(),
                fermer: { [weak self] in
                    self?.fenetre?.performClose(nil)
                }
            )
        )
        hote.sizingOptions = .preferredContentSize

        let fenetre = FenetreAccueilWindow(contentViewController: hote)
        fenetre.styleMask = [.titled, .closable, .fullSizeContentView]
        // Titre vidé mais pas absent : c'est le nom accessible de la fenêtre, et VoiceOver
        // annoncerait « fenêtre sans titre » sans lui. `titleVisibility` l'efface du bandeau.
        fenetre.title = texte("welcome.window.title")
        fenetre.titleVisibility = .hidden
        fenetre.titlebarAppearsTransparent = true
        fenetre.isMovableByWindowBackground = true
        fenetre.appearance = NSAppearance(named: .darkAqua)
        fenetre.backgroundColor = NSColor(red: 0.02, green: 0.03, blue: 0.09, alpha: 1)
        fenetre.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        fenetre.isReleasedWhenClosed = false
        fenetre.delegate = self
        fenetre.center()
        self.fenetre = fenetre

        fenetre.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hauteur du CONTENU, pour que la fenêtre entière tienne sur l'écran où elle va s'ouvrir —
    /// `center()` la pose sur l'écran principal, c'est donc celui-là qu'on mesure.
    ///
    /// La barre de titre se déduit du style plutôt que de s'estimer, mais SANS
    /// `.fullSizeContentView` : ce drapeau-là annule la différence entre cadre et contenu dans le
    /// calcul d'AppKit, alors que la fenêtre, elle, est construite AVANT qu'on le pose. MESURÉ le
    /// 2026-09-05 : la fenêtre fait bien 28 pt de plus que son contenu.
    private static func hauteurContenu() -> CGFloat {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 780
        let barreDeTitre = NSWindow.frameRect(forContentRect: .zero, styleMask: [.titled, .closable]).height
        return GeometrieAccueil.hauteurContenu(visibleFrameHeight: visible, barreDeTitre: barreDeTitre)
    }

    /// « Vu » ne s'enregistre que si Bouncer est prêt à servir. Fermer le guide après « Passer »
    /// sans avoir accordé l'Accessibilité laissait une app inerte et un guide qui ne revenait plus :
    /// tant qu'il reste quelque chose à faire, il se rouvre au lancement suivant.
    func windowWillClose(_ notification: Notification) {
        if windowManager.etatAccueil.pretAServir {
            defaults.set(true, forKey: Self.cleVue)
        }
        fenetre = nil
    }
}



// MARK: - Le tracé « hello »

/// Le mot « hello » en cursive, d'un seul trait continu, du premier jambage du `h` à la sortie du
/// `o`. Un seul sous-chemin : c'est ce qui permet à `trim(from:to:)` de le révéler comme une main
/// qui écrit, dans l'ordre où on l'écrirait. Deux sous-chemins et le trim les avancerait de front.
///
/// Le tracé n'est pas dessiné à la main : c'est la vectorisation du lettrage « hello » d'Apple
/// publiée par Michal Tynior (https://github.com/mtynior/AppleHello, MIT), transposée du repère
/// normalisé 0…1 vers un repère 0…1000. La différence n'est pas cosmétique : un tracé posé point
/// par point casse la tangente à chaque raccord, et le trait se met à craqueler dès qu'on
/// l'anime. Ici les 21 cubiques sont G1-continues (rupture de tangente ≤ 0,1° partout), donc le
/// trait coule.
///
/// Le cadrage passe par la boîte englobante réelle du chemin (`Path.boundingRect`, qui ignore les
/// points de contrôle) plutôt que par des marges devinées, et l'échelle est isotrope : le
/// lettrage se déforme si on l'étire sur les deux axes indépendamment.
struct TraceHello: Shape {
    /// Côté du repère de dessin. Les points ci-dessous sont exprimés dedans.
    private static let repere: CGFloat = 1000

    /// Épaisseur prévue du trait, en unités du repère de dessin. Sert à réserver la place que le
    /// trait déborde de la boîte englobante — sinon les extrémités arrondies sont rognées.
    /// Calée à l’œil sur un rendu hors app (16 est maigre, 28 bouche les contre-formes du `e` et du
    /// `o`) : à 20, le trait a du poids et les yeux des lettres restent ouverts.
    static let epaisseurRepere: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let brut = Self.trace()
        let boite = Self.boite
        guard boite.width > 0, boite.height > 0 else { return brut }

        let echelle = min(rect.width / boite.width, rect.height / boite.height)
        let transformation = CGAffineTransform(translationX: -boite.minX, y: -boite.minY)
            .concatenating(CGAffineTransform(scaleX: echelle, y: echelle))
            .concatenating(CGAffineTransform(
                translationX: rect.midX - boite.width * echelle / 2,
                y: rect.midY - boite.height * echelle / 2
            ))
        return brut.applying(transformation)
    }

    /// Boîte englobante du tracé, trait compris. Calculée une fois : `path(in:)` est rappelée à
    /// chaque image de l'animation, et refaire la boîte à chaque fois ne sert à rien.
    private static let boite: CGRect = trace().boundingRect
        .insetBy(dx: -epaisseurRepere / 2, dy: -epaisseurRepere / 2)

    /// Rapport largeur/hauteur du tracé, trait compris. Sert à donner au cadre exactement la forme
    /// du mot : toute autre proportion laisserait `min()` rétrécir le lettrage pour rien.
    static var proportion: CGFloat { boite.width / boite.height }

    /// Épaisseur de trait à appliquer pour un rendu de largeur `largeur`, dans la même proportion
    /// que dans le repère de dessin. Écrit ici pour que le trait grossisse avec le mot.
    static func epaisseur(pourLargeur largeur: CGFloat) -> CGFloat {
        max(1.5, epaisseurRepere * largeur / boite.width)
    }

    private static func trace() -> Path {
        var p = Path()
        let k = repere
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

        // h — hampe, boucle du haut, jambage, épaule.
        p.move(to: pt(0.18942, 0.64916))
        p.addCurve(to: pt(0.27418, 0.51669), control1: pt(0.27418, 0.51669), control2: pt(0.23809, 0.59394))
        p.addCurve(to: pt(0.30536, 0.34281), control1: pt(0.30196, 0.45722), control2: pt(0.31651, 0.37724))
        p.addCurve(to: pt(0.24651, 0.67414), control1: pt(0.26479, 0.21753), control2: pt(0.24062, 0.67407))
        p.addCurve(to: pt(0.28192, 0.51110), control1: pt(0.25240, 0.67420), control2: pt(0.25206, 0.54125))
        p.addCurve(to: pt(0.32367, 0.53984), control1: pt(0.31178, 0.48094), control2: pt(0.32230, 0.52111))
        p.addCurve(to: pt(0.31839, 0.63550), control1: pt(0.32589, 0.57011), control2: pt(0.31687, 0.61804))
        // e — montée, retour par-dessus (l'œil se ferme au croisement), puis la panse.
        p.addCurve(to: pt(0.43599, 0.55398), control1: pt(0.32473, 0.70854), control2: pt(0.42787, 0.63682))
        p.addCurve(to: pt(0.38340, 0.61147), control1: pt(0.44471, 0.46492), control2: pt(0.36830, 0.46917))
        p.addCurve(to: pt(0.44180, 0.66942), control1: pt(0.38895, 0.66377), control2: pt(0.42346, 0.67724))
        // l — hampe, boucle, descente qui s'aplatit sur la ligne de base.
        p.addCurve(to: pt(0.55200, 0.38575), control1: pt(0.50813, 0.64115), control2: pt(0.55363, 0.49671))
        p.addCurve(to: pt(0.49571, 0.60864), control1: pt(0.54988, 0.24203), control2: pt(0.47856, 0.38729))
        p.addCurve(to: pt(0.57499, 0.64351), control1: pt(0.50232, 0.69393), control2: pt(0.55841, 0.66619))
        // l — le second.
        p.addCurve(to: pt(0.64978, 0.36314), control1: pt(0.60564, 0.60157), control2: pt(0.65966, 0.48059))
        p.addCurve(to: pt(0.59745, 0.62607), control1: pt(0.63947, 0.24062), control2: pt(0.56181, 0.44249))
        p.addCurve(to: pt(0.65480, 0.65717), control1: pt(0.60934, 0.68733), control2: pt(0.64502, 0.66660))
        // o — montée, panse fermée en revenant sur soi, puis le délié de sortie.
        p.addCurve(to: pt(0.70474, 0.51817), control1: pt(0.67802, 0.63480), control2: pt(0.68550, 0.55360))
        p.addCurve(to: pt(0.76896, 0.56010), control1: pt(0.72906, 0.47340), control2: pt(0.76738, 0.50686))
        p.addCurve(to: pt(0.70263, 0.65105), control1: pt(0.77246, 0.67742), control2: pt(0.72159, 0.67749))
        p.addCurve(to: pt(0.70448, 0.51817), control1: pt(0.68627, 0.62823), control2: pt(0.68244, 0.56022))
        p.addCurve(to: pt(0.77530, 0.52099), control1: pt(0.71954, 0.48942), control2: pt(0.74363, 0.48871))
        p.addCurve(to: pt(0.80807, 0.51063), control1: pt(0.78825, 0.53419), control2: pt(0.79935, 0.53183))

        return p
    }
}

/// Le mot « hello » qui s'écrit. `trim` avance la fin du tracé de 0 à 1 : le trait naît sous une
/// main invisible plutôt que d'apparaître d'un bloc.
private struct SignatureHello: View {
    /// Largeur du mot, trait compris. La hauteur en découle : le cadre épouse le tracé, sinon
    /// l'échelle isotrope rétrécit le lettrage pour tenir dans la plus petite des deux mesures.
    var largeur: CGFloat = 300

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var avancement: CGFloat = 0

    var body: some View {
        let epaisseur = TraceHello.epaisseur(pourLargeur: largeur)

        TraceHello()
            .trim(from: 0, to: avancement)
            .stroke(style: StrokeStyle(lineWidth: epaisseur, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Nuit.encre)
            .shadow(color: Color(red: 0.55, green: 0.72, blue: 1).opacity(0.45), radius: epaisseur * 2.2)
            .frame(width: largeur, height: largeur / TraceHello.proportion)
            .onAppear {
                guard !reduceMotion else {
                    avancement = 1
                    return
                }
                avancement = 0
                // 2,1 s : le rythme d'une main qui écrit un mot court. Plus vite, l'effet se perd ;
                // plus lentement, on attend devant sa fenêtre.
                withAnimation(.easeInOut(duration: 2.1)) { avancement = 1 }
            }
            .accessibilityElement()
            .accessibilityLabel("hello")
    }
}

// MARK: - Vue principale

struct VueAccueil: View {
    @ObservedObject var windowManager: WindowManager
    /// Observé pour le raccourci affiché à l'écran du geste : il suit le réglage, pas une valeur
    /// écrite en dur qui mentait dès qu'on en choisissait un autre.
    @ObservedObject var reglages: Reglages
    var largeur: CGFloat = 660
    var hauteur: CGFloat = 580
    let fermer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var etape: EtapeAccueil = .bienvenue

    private var etat: EtatAccueil { windowManager.etatAccueil }

    var body: some View {
        VStack(spacing: 0) {
            // Les pastilles de fenêtre flottent au-dessus du dégradé : cette marge leur réserve
            // la place plutôt que de laisser le contenu passer dessous.
            Spacer(minLength: 34)

            ScrollView {
                ZStack {
                    contenu(pour: etape)
                        .id(etape)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: 26)),
                                    removal: .opacity.combined(with: .offset(x: -26))
                                )
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: GeometrieAccueil.hauteurUtile(pourHauteurFenetre: hauteur))
                .padding(.horizontal, 44)
            }
            // Le contenu tient sur un grand écran : pas de rebond, pas de barre, la fenêtre reste
            // exactement à la taille du guide. C'est seulement quand l'écran est trop court que le
            // plafond mord et que le défilement apparaît.
            .scrollBounceBehavior(.basedOnSize)

            PiedDePageAccueil(
                etape: $etape,
                avancer: avancer,
                reculer: reculer,
                fermer: fermer
            )
        }
        .frame(width: largeur, height: hauteur)
        .background(Nuit.fond)
        // Halo froid derrière le contenu : le dégradé seul est plat, ce voile lui donne un centre.
        .background(
            RadialGradient(
                colors: [Color(red: 0.20, green: 0.35, blue: 0.75).opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.32),
                startRadius: 0,
                endRadius: largeur * 0.75
            )
            .allowsHitTesting(false),
            alignment: .center
        )
    }

    @ViewBuilder
    private func contenu(pour etape: EtapeAccueil) -> some View {
        switch etape {
        case .bienvenue: pageBienvenue
        case .probleme: pageProbleme
        case .accessibilite: pageAccessibilite
        case .geste: pageGeste
        case .pret: pagePret
        }
    }

    // MARK: 1 — Bienvenue

    private var pageBienvenue: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            SignatureHello(largeur: 320)
                .padding(.bottom, 26)

            TitreEtape(texte("welcome.hello.title"))

            SousTitreEtape(texte("welcome.hello.body"))

            Spacer(minLength: 0)
        }
    }

    // MARK: 2 — Le problème

    private var pageProbleme: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            IllustrationConflit()
                .padding(.bottom, 28)

            TitreEtape(texte("welcome.problem.title"))

            SousTitreEtape(texte("welcome.problem.body"))

            Spacer(minLength: 0)
        }
    }

    // MARK: 3 — L'Accessibilité

    private var pageAccessibilite: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Sceau(
                symbole: etat.accessibiliteAccordee ? "checkmark.shield.fill" : "lock.shield.fill",
                teinte: etat.accessibiliteAccordee ? Color.green : Color.orange
            )
            .padding(.bottom, 26)

            TitreEtape(texte(etat.accessibiliteAccordee ? "welcome.access.granted.title" : "welcome.access.missing.title"))

            SousTitreEtape(
                texte(etat.accessibiliteAccordee
                    ? "welcome.access.granted.body"
                    : "welcome.access.missing.body")
            )

            if !etat.accessibiliteAccordee {
                VStack(spacing: 10) {
                    Button(texte("welcome.access.openSettings")) {
                        windowManager.openAccessibilitySettings()
                    }
                    .buttonStyle(BoutonSecondaire())
                    .accessibilityHint(texte("welcome.access.openSettings.hint"))

                    Text(texte("welcome.access.tip"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Nuit.tresDoux)
                }
                .padding(.top, 22)
            }

            Spacer(minLength: 0)
        }
        // L'état vient de `windowManager.accessibilityTrusted`, resondé toutes les 2 s : la bascule
        // au vert arrive pendant que l'utilisateur regarde, elle mérite d'être adoucie.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: etat.accessibiliteAccordee)
    }

    // MARK: 4 — Le geste

    private var pageGeste: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            SimulateurNotchInteractif()
                .padding(.bottom, 22)

            TitreEtape(texte("welcome.gesture.title"))

            SousTitreEtape(texte("welcome.gesture.body"))

            // « Aucun raccourci » n'a rien à montrer : la ligne entière disparaît plutôt que
            // d'annoncer qu'« Aucun » fait tourner le cycle.
            if reglages.raccourciGlobal != .aucun {
                HStack(spacing: 7) {
                    Text(reglages.raccourciGlobal.libelle)
                        .accessibilityLabel(reglages.raccourciGlobal.libelleAccessible)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Nuit.encre)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Nuit.trait, lineWidth: 1)
                        )

                    Text(texte("welcome.gesture.shortcutNote"))
                        .font(.system(size: 12))
                        .foregroundStyle(Nuit.doux)
                }
                .padding(.top, 16)
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: 5 — Prêt

    private var pagePret: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Sceau(
                symbole: etat.toutEnPlace ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                teinte: etat.toutEnPlace ? Color.green : Color.orange
            )
            .padding(.bottom, 22)

            TitreEtape(texte(etat.toutEnPlace ? "welcome.ready.title" : "welcome.ready.title.incomplete"))

            VStack(alignment: .leading, spacing: 9) {
                LigneBilan(
                    valide: etat.accessibiliteAccordee,
                    texte: texte(etat.accessibiliteAccordee
                        ? "welcome.ready.access.ok"
                        : "welcome.ready.access.missing")
                )
                LigneBilan(
                    valide: etat.appsAInstaller.isEmpty && !etat.uneSeuleApp,
                    texte: bilanApps
                )
                // Seulement quand elle manque : une encoche présente est la norme, une ligne
                // verte pour la dire n'apprendrait rien.
                if !etat.encochePresente {
                    LigneBilan(valide: false, texte: texte("welcome.ready.notch.missing"))
                }
            }
            .padding(.top, 18)

            VStack(spacing: 9) {
                Text(texte("welcome.ready.menuBarNote"))
                    .font(.system(size: 12))
                    .foregroundStyle(Nuit.doux)

                ApercuBarreDesMenus()
            }
            .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: etat)
    }

    private var bilanApps: String {
        if !etat.appsAInstaller.isEmpty {
            return texte("welcome.ready.noAppInstalled", etat.appsAInstaller.formatted(.list(type: .or)))
        }
        if etat.uneSeuleApp { return texte("welcome.ready.oneApp") }
        return texteAuPluriel("welcome.ready.appsFound", windowManager.entreesMenu.count)
    }



    private func avancer() {
        guard let suivante = etape.suivante else {
            fermer()
            return
        }
        changer(vers: suivante)
    }

    private func reculer() {
        guard let precedente = etape.precedente else { return }
        changer(vers: precedente)
    }

    private func changer(vers cible: EtapeAccueil) {
        if reduceMotion {
            etape = cible
        } else {
            withAnimation(.easeInOut(duration: 0.28)) { etape = cible }
        }
    }
}

// MARK: - Éléments de mise en page

private struct TitreEtape: View {
    let texte: String
    init(_ texte: String) { self.texte = texte }

    var body: some View {
        Text(texte)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(Nuit.encre)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SousTitreEtape: View {
    let texte: String
    init(_ texte: String) { self.texte = texte }

    var body: some View {
        Text(texte)
            .font(.system(size: 13.5))
            .foregroundStyle(Nuit.doux)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 460)
            .padding(.top, 12)
    }
}

/// Le grand symbole rond des écrans qui n'ont pas d'illustration propre.
private struct Sceau: View {
    let symbole: String
    let teinte: Color

    var body: some View {
        Image(systemName: symbole)
            .font(.system(size: 52, weight: .regular))
            .foregroundStyle(teinte)
            .shadow(color: teinte.opacity(0.45), radius: 22)
            .frame(height: 72)
            .accessibilityHidden(true)
    }
}

private struct LigneBilan: View {
    let valide: Bool
    let texte: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: valide ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 13))
                .foregroundStyle(valide ? Color.green : Color.orange)
                .accessibilityHidden(true)

            Text(texte)
                .font(.system(size: 12.5))
                .foregroundStyle(Nuit.doux)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Boutons

/// Le bouton d'un écran qui envoie ailleurs (les Réglages Système) : présent, mais pas au même
/// rang que « Continuer ».
private struct BoutonSecondaire: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Corps(configuration: configuration) }

    private struct Corps: View {
        let configuration: ButtonStyleConfiguration

        @State private var survol = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Nuit.encre)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.24 : (survol ? 0.18 : 0.12)))
                )
                .overlay(Capsule().strokeBorder(Nuit.trait, lineWidth: 1))
                .onHover { survol = $0 }
        }
    }
}

// MARK: - Illustration du conflit (écran 2)

/// Trois fenêtres d'encoche empilées au même endroit : la dernière lancée couvre les autres.
/// Dessinée plutôt que capturée — une capture d'écran vieillirait au premier redesign des apps
/// concernées, et il en faudrait une par thème.
private struct IllustrationConflit: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsation = false

    private let couches: [(nom: String, couleur: Color, decalage: CGFloat)] = [
        ("Vibe Island", .orange, 22),
        ("Boring Notch", .green, 11),
        ("NotchNook", .pink, 0),
    ]

    /// Même géométrie d'encoche que partout ailleurs : la hauteur est choisie pour la maquette,
    /// la largeur suit les proportions du vrai boîtier (`boitierEncocheReference`, BouncerCore).
    private let hauteurBoitier: CGFloat = 26
    private var largeurBoitier: CGFloat {
        let boitier = boitierEncocheReference
        return (hauteurBoitier * boitier.width / boitier.height).rounded()
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Nuit.trait, lineWidth: 1)
                )
                .frame(width: 330, height: 150)

            // La contention respire en rouge sous l'encoche, sans pictogramme d'alerte : c'est
            // l'endroit du conflit qu'on montre, pas un message d'erreur. Posée ici plutôt qu'en
            // fond de l'encoche, où le flou débordait au-dessus de la maquette.
            Capsule()
                .fill(Color.red.opacity(pulsation ? 0.32 : 0.08))
                .frame(width: 150, height: 30)
                .blur(radius: 18)
                .padding(.top, 24)
                .allowsHitTesting(false)

            // Les trois panneaux, décalés juste assez pour qu'on voie qu'ils sont trois.
            ForEach(Array(couches.enumerated()), id: \.offset) { index, couche in
                HStack(spacing: 7) {
                    Circle()
                        .fill(couche.couleur)
                        .frame(width: 7, height: 7)
                    Text(couche.nom)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(width: 168, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(white: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(couche.couleur.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
                )
                .offset(x: couche.decalage - 22, y: 42 + CGFloat(index) * 23)
            }

            // L'encoche physique, par-dessus : c'est le point de contention.
            EncochePhysiqueShape()
                .fill(Color.black)
                .frame(width: largeurBoitier, height: hauteurBoitier)

        }
        .frame(width: 330, height: 150)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsation = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(texte("welcome.problem.illustration"))
    }
}

// MARK: - Aperçu Barre des Menus

private struct ApercuBarreDesMenus: View {
    var body: some View {
        HStack(spacing: 0) {
            // Côté gauche : menus factices
            HStack(spacing: 11) {
                Text("")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Finder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(texte("welcome.ready.fakeMenu.file"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
            .padding(.leading, 12)

            Spacer()

            // Côté droit : statut & Bouncer en vedette
            HStack(spacing: 9) {
                // Icône Bouncer mise en valeur. PAS de libellé « Bouncer » à côté : `MenuBarExtra`
                // n'affiche qu'un symbole monochrome, son titre ne sert que de nom accessible.
                // L'aperçu montrait le mot, et envoyait donc chercher dans la barre des menus
                // quelque chose qui ne s'y trouve jamais.
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    )
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 3, x: 0, y: 1)

                Image(systemName: "wifi")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))

                Image(systemName: "battery.100")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.55))

                Text("10:42")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.trailing, 10)
        }
        .frame(width: 380, height: 30)
        // Couleurs écrites plutôt que sémantiques : cet aperçu vit sur le dégradé bleu nuit du
        // parcours, où `.windowBackgroundColor` peindrait une barre gris clair.
        .background(
            Color(white: 0.17),
            in: RoundedRectangle(cornerRadius: 7.5, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texte("welcome.ready.menuBarPreview"))
    }
}

// MARK: - Simulateur Interactif d'Encoche et Geste

private struct SimulateurNotchInteractif: View {
    struct AppSimulee: Identifiable {
        let id: Int
        let nom: String
        let sousTitre: String
        let icone: String
        let couleur: Color
    }

    private let apps: [AppSimulee] = [
        AppSimulee(id: 0, nom: texte("welcome.sim.app1.name"), sousTitre: texte("welcome.sim.app1.subtitle"), icone: "music.note", couleur: .pink),
        AppSimulee(id: 1, nom: "Boring Notch", sousTitre: texte("welcome.sim.app2.subtitle"), icone: "battery.100.bolt", couleur: .green),
        AppSimulee(id: 2, nom: "Vibe Island", sousTitre: texte("welcome.sim.app3.subtitle"), icone: "bell.badge.fill", couleur: .orange),
    ]

    /// L'encoche dessinée ici l'est à l'échelle du simulateur, pas à celle de l'écran : seule sa
    /// HAUTEUR est choisie pour la maquette (25 pt dans un écran figuré de 122), la largeur suit
    /// les proportions du vrai boîtier. Sans ça, deux vues finissent avec deux encoches de formes
    /// différentes — c'est arrivé, 130 pt ici contre 166 dans les réglages — et la règle « zéro
    /// hardcoding d'encoche » du CLAUDE.md tombe (cf. `boitierEncocheReference`, BouncerCore).
    private let hauteurBoitierDessine: CGFloat = 25
    private var largeurBoitierDessine: CGFloat {
        let boitier = boitierEncocheReference
        return (hauteurBoitierDessine * boitier.width / boitier.height).rounded()
    }

    /// De combien chaque flèche déborde du boîtier. C'est l'équivalent maquette de `margeLaterale` :
    /// les flèches vivent à CÔTÉ du boîtier, jamais dessous, sinon le matériel les cache.
    private let debordementFleches: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var indexActif: Int = 0
    @State private var positionDoigtsX: CGFloat = 0
    @State private var sensDernierGeste: String = "droite"
    @State private var estSurvole: Bool = false

    private let timer = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    var body: some View {
        // Largeur figée : la maquette d'un écran de Mac ne gagne rien à s'étirer sur toute la
        // page, et l'encoche y paraîtrait minuscule.
        VStack(spacing: 10) {
            // Visualisation de l'écran & de l'encoche
            ZStack(alignment: .top) {
                // Fond sombre simulant l'écran Retina
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.12), Color(white: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 122)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )

                // L'encoche physique (Notch)
                ZStack(alignment: .top) {
                    EncochePhysiqueShape()
                        .fill(Color.black)
                        .frame(width: largeurBoitierDessine, height: hauteurBoitierDessine)
                        .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 2)

                    // Capteur caméra discret
                    Circle()
                        .fill(Color(white: 0.22))
                        .frame(width: 4.5, height: 4.5)
                        .padding(.top, 6.5)
                }
                .accessibilityHidden(true)

                // Flèches latérales ‹ et › (cliquables)
                HStack(spacing: largeurBoitierDessine + 2 * debordementFleches) {
                    // Les flèches portent un SENS, contrairement au swipe : c'est toute la
                    // distinction que ce simulateur doit enseigner (cf. Swipe.swift, « une flèche
                    // qui pointe à gauche et envoie à droite mentirait »). ‹ recule, › avance,
                    // exactement comme `NotchArrowsView` dans l'app réelle.
                    BoutonFlecheEncoche(
                        symbole: "chevron.left",
                        libelleAccessible: texte("welcome.sim.arrow.previous.label"),
                        indication: texte("welcome.sim.arrow.previous.hint")
                    ) {
                        parFleche(avance: false)
                    }
                    .help(texte("welcome.sim.arrow.previous.tooltip"))

                    BoutonFlecheEncoche(
                        symbole: "chevron.right",
                        libelleAccessible: texte("welcome.sim.arrow.next.label"),
                        indication: texte("welcome.sim.arrow.next.hint")
                    ) {
                        parFleche(avance: true)
                    }
                    .help(texte("welcome.sim.arrow.next.tooltip"))
                }
                .padding(.top, 2.5)

                // Contenu de l'app sous l'encoche
                VStack(spacing: 7) {
                    Spacer().frame(height: 30)

                    let app = apps[indexActif]
                    HStack(spacing: 7) {
                        Image(systemName: app.icone)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(app.couleur)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 0.5) {
                            Text(app.nom)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white)

                            Text(app.sousTitre)
                                .font(.system(size: 9))
                                .foregroundStyle(Color(white: 0.75))
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.75))
                            .overlay(
                                Capsule()
                                    .strokeBorder(app.couleur.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 5, x: 0, y: 2)
                    .id(indexActif)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.combined(with: .scale(scale: 1.04))
                            )
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(texte("welcome.sim.app.label", app.nom, app.sousTitre))

                    Spacer().frame(height: 3)

                    // Indicateur de cycle (1, 2, 3)
                    HStack(spacing: 4.5) {
                        ForEach(apps.indices, id: \.self) { i in
                            Circle()
                                .fill(i == indexActif ? Color.white : Color.white.opacity(0.25))
                                .frame(width: i == indexActif ? 5.5 : 4, height: i == indexActif ? 5.5 : 4)
                        }
                    }
                    .accessibilityHidden(true)
                }

                // Doigts de swipe sur le trackpad
                VStack {
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(sensDernierGeste == "gauche" ? Color.accentColor : Color.white.opacity(0.3))

                        // Deux doigts qui glissent
                        HStack(spacing: 4.5) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                        }
                        .offset(x: positionDoigtsX)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(sensDernierGeste == "droite" ? Color.accentColor : Color.white.opacity(0.3))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                    .padding(.bottom, 7)
                }
                .accessibilityHidden(true)
            }
            .frame(height: 122)
            .onHover { survole in
                estSurvole = survole
            }

        }
        .frame(width: 420)
        .onReceive(timer) { _ in
            guard !reduceMotion && !estSurvole else { return }
            animerSwipeAutomatique()
        }
    }

    /// Un clic sur une flèche : le sens compte, et il ne touche pas à l'indicateur de swipe —
    /// « swipe gauche ➔ avance » resterait vrai, mais l'afficher après un clic sur ‹ laisserait
    /// croire que la flèche et le geste font la même chose. Ils font justement le contraire.
    private func parFleche(avance: Bool) {
        deplacer(de: avance ? 1 : -1, decalageDoigts: 0)
    }

    /// Un swipe : quel que soit son sens, il AVANCE d'un cran. C'est la dynamique réelle de
    /// l'app (cf. `NotchOverlay.handleScroll`, toujours `forward: true`).
    private func basculer(vers sens: String) {
        sensDernierGeste = sens
        deplacer(de: 1, decalageDoigts: sens == "droite" ? 16 : -16)
    }

    private func deplacer(de pas: Int, decalageDoigts: CGFloat) {
        let cible = (indexActif + pas + apps.count) % apps.count
        if reduceMotion {
            indexActif = cible
            positionDoigtsX = 0
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                indexActif = cible
                positionDoigtsX = decalageDoigts
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.18)) {
                    positionDoigtsX = 0
                }
            }
        }
    }

    private func animerSwipeAutomatique() {
        let nouveauSens = sensDernierGeste == "droite" ? "gauche" : "droite"
        basculer(vers: nouveauSens)
    }
}

// MARK: - Découpe de l'Encoche Physique

private struct EncochePhysiqueShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 8

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

// MARK: - Bouton Flèche de l'Encoche

private struct BoutonFlecheEncoche: View {
    let symbole: String
    let libelleAccessible: String
    /// Ce que fait CE bouton-là. Figée sur « fait avancer le cycle », elle mentait sur ‹.
    let indication: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var estFocus: Bool
    @State private var survol: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 21, height: 21)
                .background(
                    Circle()
                        .fill(Color(white: 0.20).opacity(survol ? 0.95 : 0.70))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            estFocus ? Color.accentColor : Color.white.opacity(survol ? 0.4 : 0.15),
                            lineWidth: estFocus ? 2 : 1
                        )
                )
                .scaleEffect(reduceMotion ? 1.0 : (survol || estFocus ? 1.08 : 1.0))
        }
        .buttonStyle(.plain)
        .focused($estFocus)
        .accessibilityLabel(libelleAccessible)
        .accessibilityHint(indication)
        .onHover { s in
            if reduceMotion {
                survol = s
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    survol = s
                }
            }
        }
    }
}
