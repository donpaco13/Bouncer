//
// FenetreReglages.swift — la fenêtre de préférences.
//
// C'est une scène `Settings`, pas une `NSWindow` montée à la main comme `FenetreAccueil`. Ce
// n'est pas une économie de code : c'est ce qui rend la fenêtre reconnaissable. macOS lui donne
// alors gratuitement le titre localisé « Réglages », la barre d'onglets d'un panneau de
// préférences, le raccourci ⌘, et la position mémorisée d'une session à l'autre — quatre choses
// qu'une fenêtre maison rate toujours un peu, et qui font la différence entre un panneau de debug
// et un produit. `SettingsLink` (macOS 14) est la seule façon de l'ouvrir depuis un `MenuBarExtra` :
// un `NSApp.sendAction(showSettingsWindow:)` marche par accident et casse d'une version à l'autre.
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

    var body: some View {
        TabView {
            OngletGeneral(reglages: reglages)
                .tabItem { Label("Général", systemImage: "gearshape") }
            OngletGeste(reglages: reglages)
                .tabItem { Label("Geste", systemImage: "hand.draw") }
            OngletApplications(windowManager: windowManager, reglages: reglages)
                .tabItem { Label("Applications", systemImage: "square.stack") }
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

    var body: some View {
        Form {
            Section {
                Toggle("Lancer Bouncer à l'ouverture de session", isOn: Binding(
                    get: { demarrage.actif },
                    set: { demarrage.definir($0) }
                ))

                Text("Bouncer n'arbitre l'encoche que pendant qu'il tourne. Sans lancement automatique, il faut y penser à chaque démarrage.")
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
                Picker("Vérifier les apps toutes les", selection: $reglages.intervalleRafraichissement) {
                    ForEach(Reglages.Domaine.intervalles, id: \.self) { intervalle in
                        Text(libelle(intervalle)).tag(intervalle)
                    }
                }
                Text("Fréquence à laquelle Bouncer regarde quelles apps occupent l'encoche et si l'autorisation d'Accessibilité a changé. Plus court : le menu se met à jour plus vite. Plus long : moins de travail en arrière-plan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // Le réglage vit dans macOS, pas chez nous : il a pu changer dans Réglages Système
        // pendant que cette fenêtre était fermée.
        .onAppear { demarrage.relire() }
    }

    private func libelle(_ intervalle: TimeInterval) -> String {
        intervalle == 1 ? "1 seconde" : "\(Int(intervalle)) secondes"
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
            ? "macOS attend votre accord : ouvrez Réglages Système › Général › Ouverture et éléments autorisés, et activez Bouncer."
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
            avertissement = "macOS a refusé : \(error.localizedDescription)"
        }
    }
}

// MARK: - Geste

private struct OngletGeste: View {
    @ObservedObject var reglages: Reglages

    var body: some View {
        Form {
            Section {
                Picker("Faire tourner le cycle avec", selection: $reglages.modeActivation) {
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

            Section("Flèches") {
                // La valeur est dans le libellé du curseur, pas sur une ligne à part : un
                // panneau de préférences se lit d'un coup d'œil, et « Réglage actuel : 72 pt »
                // sur sa propre ligne doublait la hauteur de la section pour redire le curseur.
                Slider(value: $reglages.porteeApproche, in: Reglages.Domaine.portee, step: 4) {
                    Text("Apparition — \(libellePortee)")
                } minimumValueLabel: {
                    Text("Au survol")
                } maximumValueLabel: {
                    Text("De loin")
                }
                .accessibilityLabel("Distance d'apparition des flèches")
                .accessibilityValue(reglages.porteeApproche == 0 ? "0 point, uniquement dans la bande de l'encoche" : "\(Int(reglages.porteeApproche)) points")

                Text("L'opacité des flèches suit la distance du curseur à l'encoche. Ce réglage dit où la montée commence.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Slider(value: $reglages.margeLaterale, in: Reglages.Domaine.marge, step: 2) {
                    Text("Bandes latérales — \(Int(reglages.margeLaterale)) pt de chaque côté")
                } minimumValueLabel: {
                    Text("Étroites")
                } maximumValueLabel: {
                    Text("Larges")
                }
                .accessibilityLabel("Largeur des bandes latérales des flèches")
                .accessibilityValue("\(Int(reglages.margeLaterale)) points de chaque côté")

                Text("Les flèches se logent de part et d'autre du boîtier caméra, jamais dessus. Élargir donne une cible de clic plus facile ; réduire laisse la barre des menus tranquille.")
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
                    Button("Rétablir les valeurs d'origine") { reglages.reinitialiser() }
                        .accessibilityHint("Restaure la portée d'apparition et les marges à leurs valeurs d'origine")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var libellePortee: String {
        reglages.porteeApproche == 0
            ? "Uniquement dans la bande de l'encoche"
            : "\(Int(reglages.porteeApproche)) pt avant la bande"
    }
}

/// L'encoche, ses deux bandes latérales et la portée d'approche, à l'échelle relative des
/// réglages en cours. Dessiné plutôt qu'illustré : c'est le seul moyen qu'un curseur de « 72 pt »
/// veuille dire quelque chose avant d'aller l'essayer sur l'écran.
private struct ApercuGeste: View {
    @ObservedObject var reglages: Reglages

    /// Largeur du boîtier caméra mesurée sur la machine de référence (cf. ZoneSurvolTests) :
    /// l'aperçu garde les proportions réelles au lieu d'inventer une encoche décorative.
    private let largeurBoitier: CGFloat = 166

    var body: some View {
        GeometryReader { geo in
            let echelle = geo.size.width / (largeurBoitier + 2 * Reglages.Domaine.marge.upperBound + 2 * Reglages.Domaine.portee.upperBound)
            let marge = reglages.margeLaterale * echelle
            let portee = reglages.porteeApproche * echelle

            ZStack {
                if reglages.modeActivation.flechesActives {
                    // Le halo figure la rampe d'opacité : il s'étale exactement sur la portée.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.accentColor.opacity(0), .accentColor.opacity(0.28), .accentColor.opacity(0)],
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
            return "Aperçu : l'encoche seule, sans flèche — le mode choisi ne les affiche pas."
        }
        return "Aperçu : l'encoche, une bande de \(Int(reglages.margeLaterale)) points de chaque côté portant une flèche, et une zone d'approche de \(Int(reglages.porteeApproche)) points au-delà."
    }
}

// MARK: - Applications

private struct OngletApplications: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var reglages: Reglages

    var body: some View {
        let entrees = windowManager.entreesMenu
        let retenues = entrees.filter { !reglages.bundleIDsExclus.contains($0.bundleID) }

        Form {
            Section {
                if entrees.isEmpty {
                    Text("Aucune app d'encoche détectée sur ce Mac. Elles apparaîtront ici dès que Bouncer en verra une.")
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
                Text("Apps parcourues par le swipe et les flèches")
            } footer: {
                if entrees.isEmpty {
                    EmptyView()
                } else if retenues.isEmpty {
                    Label {
                        Text("Toutes les apps sont décochées : le geste n'a plus rien à parcourir. Le menu de la barre des menus, lui, continue de les lister.")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Une app décochée reste dans le menu et reste cliquable — elle n'apparaît simplement plus dans le cycle. Utile pour une app d'encoche qu'on garde ouverte en permanence.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}
