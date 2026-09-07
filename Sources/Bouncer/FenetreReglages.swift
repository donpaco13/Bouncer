//
// FenetreReglages.swift — la fenêtre de préférences.
//
// C'est une scène `Settings`, pas une `NSWindow` montée à la main comme `FenetreAccueil`. Ce
// n'est pas une économie de code : c'est ce qui rend la fenêtre reconnaissable. macOS lui donne
// alors gratuitement le titre localisé « Réglages », la barre d'onglets d'un panneau de
// préférences, le raccourci ⌘, et la position mémorisée d'une session à l'autre — quatre choses
// qu'une fenêtre maison rate toujours un peu, et qui font la différence entre un panneau de debug
// et un produit. Ce qui l'OUVRE depuis le `MenuBarExtra`, en revanche, n'est pas `SettingsLink` :
// cette voie-là a été essayée et l'entrée disparaissait du menu après le premier lancement. Le
// relevé et les deux autres voies écartées sont dans `MenuBarContentView.ouvrirReglages()`, qui
// est le seul endroit d'où cette fenêtre s'ouvre.
//
// Trois onglets, dans l'ordre où on en a besoin : Général (ce qui concerne l'app), Geste (ce qui
// concerne la sensation), Applications (ce que le cycle parcourt).
//
// PARTI PRIS SUR LES DÉFAUTS : aucune valeur proposée ici n'est nouvelle. Portée 72 pt, marge
// 44 pt, resondage 2 s sont exactement les constantes qui étaient dans le code. Le rôle de cette
// fenêtre est de les rendre réglables, pas de décider à la place de qui s'en sert de ce qui
// « semble bien ».

import BouncerCore
import ServiceManagement
import SwiftUI

struct VueReglages: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var reglages: Reglages
    @ObservedObject var raccourci: RaccourciGlobalController

    var actionRelance: () -> Void = { RelanceurApp.partage.relancer() }

    var body: some View {
        TabView {
            OngletGeneral(reglages: reglages, actionRelance: actionRelance)
                .tabItem { Label(texte("settings.tab.general"), systemImage: "gearshape") }
            OngletGeste(reglages: reglages, raccourci: raccourci)
                .tabItem { Label(texte("settings.tab.gesture"), systemImage: "hand.draw") }
            OngletApplications(windowManager: windowManager, reglages: reglages)
                .tabItem { Label(texte("settings.tab.apps"), systemImage: "square.stack") }
        }
        // Taille fixe, et c'est voulu : MESURÉ, la scène `Settings` fige la hauteur de la
        // fenêtre sur le premier onglet et ne la reprend pas en changeant d'onglet — laisser la
        // hauteur libre donnait donc une barre de défilement dans « Geste » pendant que
        // « Général » gardait du vide. La hauteur est celle du plus haut des trois panneaux ;
        // l'onglet « Applications » défile au-delà de quelques apps, ce qui est le comportement
        // attendu d'une liste.
        .frame(width: 480, height: 576)
    }
}

// MARK: - Général

private struct OngletGeneral: View {
    @ObservedObject var reglages: Reglages
    @StateObject private var demarrage = LancementAuDemarrage()
    var actionRelance: () -> Void = { RelanceurApp.partage.relancer() }

    var body: some View {
        Form {
            Section {
                Toggle(texte("settings.general.launchAtLogin"), isOn: Binding(
                    get: { demarrage.actif },
                    set: { demarrage.definir($0) }
                ))

                Text(texte("settings.general.launchAtLogin.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let avertissement = demarrage.avertissement {
                    Label {
                        Text(avertissement)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Picker(texte("settings.general.refresh"), selection: $reglages.intervalleRafraichissement) {
                    ForEach(Reglages.Domaine.intervalles, id: \.self) { intervalle in
                        Text(libelle(intervalle)).tag(intervalle)
                    }
                }
                Text(texte("settings.general.refresh.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // La langue et le bouton de relance dans la MÊME section : le changement s'applique
            // tout de suite à tout ce que Bouncer écrit lui-même, mais le titre de la fenêtre
            // vient de macOS et ne suit qu'à la relance — le bouton qui la fait est donc à côté
            // de la note qui la demande.
            Section {
                Picker(texte("settings.general.language"), selection: $reglages.langue) {
                    ForEach(LangueInterface.allCases) { langue in
                        Text(langue.nomNatif).tag(langue)
                    }
                }
                Text(texte("settings.general.language.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(texte("settings.general.relaunch")) {
                        actionRelance()
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Le réglage vit dans macOS, pas chez nous : il a pu changer dans Réglages Système
        // pendant que cette fenêtre était fermée.
        .onAppear { demarrage.relire() }
    }

    private func libelle(_ intervalle: TimeInterval) -> String {
        texteAuPluriel("settings.general.refresh.interval", Int(intervalle))
    }
}

/// L'élément de lancement au démarrage de session.
@MainActor
private final class LancementAuDemarrage: ObservableObject {
    @Published private(set) var actif = false
    /// Ce qui empêche la case de refléter le souhait de l'utilisateur, dit en clair. `nil` quand
    /// tout va bien. Sans ça, une case qui se décoche toute seule ne s'explique pas.
    @Published private(set) var avertissement: String?

    init() { relire() }

    /// Le statut de `SMAppService` est la SEULE source de vérité — pas de copie dans
    /// `UserDefaults`. L'utilisateur peut décocher Bouncer dans Réglages Système › Général ›
    /// Ouverture et éléments autorisés, et une case qui refléterait notre propre copie mentirait
    /// à partir de cet instant.
    func relire() {
        let statut = SMAppService.mainApp.status
        actif = statut == .enabled
        avertissement = statut == .requiresApproval
            ? texte("settings.general.launchAtLogin.needsApproval")
            : nil
    }

    func definir(_ souhaite: Bool) {
        do {
            if souhaite {
                // MESURÉ : avant tout enregistrement, `status` vaut `.notFound` (3) même pour une
                // app correctement installée dans /Applications — et `register()` réussit quand
                // même. Ce statut ne dit donc RIEN sur la faisabilité : le seul moyen de savoir
                // est d'essayer, et de lire le statut après coup.
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            relire()
        } catch {
            actif = SMAppService.mainApp.status == .enabled
            avertissement = texte("settings.general.launchAtLogin.refused", error.localizedDescription)
        }
    }
}

// MARK: - Geste

private struct OngletGeste: View {
    @ObservedObject var reglages: Reglages
    @ObservedObject var raccourci: RaccourciGlobalController

    var body: some View {
        Form {
            Section {
                Picker(texte("settings.gesture.trigger"), selection: $reglages.modeActivation) {
                    ForEach(ModeActivation.allCases) { mode in
                        Text(mode.libelle).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(reglages.modeActivation.explication)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(texte("settings.gesture.shortcut.header")) {
                Picker(texte("settings.gesture.shortcut"), selection: $reglages.raccourciGlobal) {
                    ForEach(RaccourciGlobal.allCases) { combinaison in
                        Text(combinaison.libelle)
                            .accessibilityLabel(combinaison.libelleAccessible)
                            .tag(combinaison)
                    }
                }
                // Le raccourci marche quelle que soit l'app au premier plan, et il PRÉEMPTE la
                // combinaison : le dire est le minimum, puisque l'utilisateur ne peut pas le
                // déduire de l'écran.
                Text(texte("settings.gesture.shortcut.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Un raccourci refusé par le système ne se voit nulle part ailleurs : le picker
                // affiche fièrement la combinaison choisie, et rien ne se passe quand on l'utilise.
                if let echec = raccourci.erreur {
                    Label(echec, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(texte("settings.gesture.zone.header")) {
                Picker(texte("settings.gesture.zone"), selection: $reglages.ancrageZone) {
                    ForEach(AncrageZone.allCases) { a in Text(a.libelle).tag(a) }
                }
                .pickerStyle(.inline)

                Text(reglages.ancrageZone.explication)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Le chiffre plutôt que l'adjectif : c'est lui qui rend le réglage décidable, et
                // c'est la mesure qui a expliqué les swipes ratés.
                Text(texte("settings.gesture.zone.measured"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(texte("settings.gesture.arrows.header")) {
                // La valeur est dans le libellé du curseur, pas sur une ligne à part : un
                // panneau de préférences se lit d'un coup d'œil, et « Réglage actuel : 72 pt »
                // sur sa propre ligne doublait la hauteur de la section pour redire le curseur.
                Slider(value: $reglages.porteeApproche, in: Reglages.Domaine.portee, step: 4) {
                    Text(texte("settings.gesture.reveal", libellePortee))
                } minimumValueLabel: {
                    Text(texte("settings.gesture.reveal.min"))
                } maximumValueLabel: {
                    Text(texte("settings.gesture.reveal.max"))
                }
                .accessibilityLabel(texte("settings.gesture.reveal.label"))
                .accessibilityValue(reglages.porteeApproche == 0 ? texte("settings.gesture.reveal.value.zero") : texte("settings.gesture.points", Int(reglages.porteeApproche)))

                Text(texte("settings.gesture.reveal.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Slider(value: $reglages.margeLaterale, in: Reglages.Domaine.marge, step: 2) {
                    Text(texte("settings.gesture.margin", Int(reglages.margeLaterale)))
                } minimumValueLabel: {
                    Text(texte("settings.gesture.margin.min"))
                } maximumValueLabel: {
                    Text(texte("settings.gesture.margin.max"))
                }
                .accessibilityLabel(texte("settings.gesture.margin.label"))
                .accessibilityValue(texte("settings.gesture.margin.value", Int(reglages.margeLaterale)))

                Text(texte("settings.gesture.margin.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Slider(value: $reglages.retraitFleches, in: Reglages.Domaine.retrait, step: 1) {
                    Text(texte("settings.gesture.slide", libelleRetrait))
                } minimumValueLabel: {
                    Text(texte("settings.gesture.slide.min"))
                } maximumValueLabel: {
                    Text(texte("settings.gesture.slide.max"))
                }
                .accessibilityLabel(texte("settings.gesture.slide.label"))
                .accessibilityValue(reglages.retraitFleches == 0 ? texte("settings.gesture.slide.value.zero") : texte("settings.gesture.points", Int(reglages.retraitFleches)))

                Text(texte("settings.gesture.slide.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Grisé plutôt que caché : la disparition de deux curseurs ferait croire à une perte,
            // et le lien avec le mode choisi juste au-dessus resterait à deviner.
            .disabled(!reglages.modeActivation.flechesActives)

            Section {
                ApercuGeste(reglages: reglages)
                HStack {
                    Spacer()
                    Button(texte("settings.gesture.reset")) { reglages.reinitialiser() }
                        .accessibilityHint(texte("settings.gesture.reset.hint"))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var libelleRetrait: String {
        reglages.retraitFleches == 0
            ? texte("settings.gesture.slide.summary.zero")
            : texte("settings.gesture.slide.summary", Int(reglages.retraitFleches))
    }

    private var libellePortee: String {
        reglages.porteeApproche == 0
            ? texte("settings.gesture.reveal.summary.zero")
            : texte("settings.gesture.reveal.summary", Int(reglages.porteeApproche))
    }
}

/// L'encoche, ses deux bandes latérales et la portée d'approche, à l'échelle relative des
/// réglages en cours. Dessiné plutôt qu'illustré : c'est le seul moyen qu'un curseur de « 72 pt »
/// veuille dire quelque chose avant d'aller l'essayer sur l'écran.
private struct ApercuGeste: View {
    @ObservedObject var reglages: Reglages

    /// Largeur du boîtier caméra de CETTE machine, ou le relevé de référence à défaut d'encoche :
    /// l'aperçu garde les proportions réelles au lieu d'inventer une encoche décorative. Source
    /// unique avec le simulateur du guide (`boitierEncocheReference`, BouncerCore).
    private var largeurBoitier: CGFloat { boitierEncocheReference.width }

    var body: some View {
        GeometryReader { geo in
            let echelle = geo.size.width / (largeurBoitier + 2 * Reglages.Domaine.marge.upperBound + 2 * Reglages.Domaine.portee.upperBound)
            let marge = reglages.margeLaterale * echelle
            let portee = reglages.porteeApproche * echelle

            ZStack {
                if reglages.modeActivation.flechesActives {
                    // La bande figure l'ÉTENDUE de la portée, et le dégradé la rampe d'opacité qui
                    // s'y joue. Elle est en gris et non en couleur d'accentuation : l'overlay ne
                    // dessine aucun halo lumineux — ce qui s'estompe ET GLISSE, ce sont les
                    // flèches elles-mêmes (`revelationFleches`, BouncerCore). Un
                    // aperçu qui invente un effet que le produit n'a pas se fait démentir au
                    // premier essai sur l'écran.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.primary.opacity(0), .primary.opacity(0.12), .primary.opacity(0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: largeurBoitier * echelle + 2 * marge + 2 * portee, height: 30)
                }

                HStack(spacing: 0) {
                    bande(largeur: marge, symbole: "chevron.left")
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        .frame(width: largeurBoitier * echelle, height: 20)
                    bande(largeur: marge, symbole: "chevron.right")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 52)
        .accessibilityElement()
        .accessibilityLabel(descriptionAccessible)
    }

    private func bande(largeur: CGFloat, symbole: String) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: largeur, height: 20)
            if reglages.modeActivation.flechesActives {
                Image(systemName: symbole)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var descriptionAccessible: String {
        guard reglages.modeActivation.flechesActives else {
            return texte("settings.gesture.preview.noArrows")
        }
        return texte("settings.gesture.preview", Int(reglages.margeLaterale), Int(reglages.porteeApproche))
    }
}

// MARK: - Applications

private struct OngletApplications: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var reglages: Reglages

    var body: some View {
        let entrees = windowManager.entreesMenu
        let retenues = entrees.filter { !reglages.bundleIDsExclus.contains($0.bundleID) }
        let orphelines = reglages.exclusionsOrphelines(dans: entrees)

        Form {
            Section {
                if entrees.isEmpty {
                    Text(texte("settings.apps.empty"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(entrees) { entree in
                        Toggle(isOn: Binding(
                            get: { !reglages.bundleIDsExclus.contains(entree.bundleID) },
                            set: { reglages.exclusion(entree.bundleID, exclue: !$0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entree.nom)
                                Text(entree.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(texte("settings.apps.header"))
            } footer: {
                if entrees.isEmpty {
                    EmptyView()
                } else if retenues.isEmpty {
                    Label {
                        Text(texte("settings.apps.allUnchecked"))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(texte("settings.apps.note"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !orphelines.isEmpty {
                Section {
                    ForEach(orphelines, id: \.self) { bundleID in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bundleID)
                                Text(texte("settings.apps.orphan.detail"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(texte("settings.apps.orphan.remove")) {
                                reglages.retirerExclusion(bundleID)
                            }
                        }
                    }
                } header: {
                    Text(texte("settings.apps.orphan.header"))
                } footer: {
                    Text(texte("settings.apps.orphan.note"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}
