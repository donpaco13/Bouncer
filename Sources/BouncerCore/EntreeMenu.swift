//
// EntreeMenu.swift — ce que le menu montre, et comment on le construit.
//
// Le menu ne lit plus `NotchAppInfo` directement. Il affichait « Vibe Island — Régissable » :
// « Régissable » est le verdict d'un test interne, du vocabulaire de développeur, et ça ne répond
// à aucune des deux questions que l'utilisateur se pose devant ce menu — laquelle occupe le notch
// en ce moment, et comment en désigner une autre. Le verdict, lui, ne disparaît pas : il devient
// une information secondaire (infobulle), parce qu'il explique pourquoi une bascule est
// instantanée et l'autre prend une seconde. Il cesse en revanche d'être une raison de griser
// l'entrée — rendre les apps résistantes pilotables est tout l'objet du chantier en cours.

import Foundation

/// Une ligne du menu. Un modèle d'affichage, pas un modèle de domaine : il n'a que ce qu'il faut
/// pour dessiner la ligne et savoir quoi appeler au clic.
public struct EntreeMenu: Identifiable, Equatable {
    /// Ce que la ligne dit de l'app. C'est l'état produit, pas le verdict technique.
    public enum Etat: Equatable {
        /// Occupe le notch. Une seule entrée à la fois.
        case active
        /// N'occupe pas le notch. Cliquable, qu'elle soit lancée ou non, régissable ou non.
        case inactive
        /// Bascule en cours. La voie par cycle de vie prend environ une seconde : sans ce retour
        /// visuel l'utilisateur clique deux fois, et la deuxième bascule annule la première.
        case enCours
    }

    public var id: String { bundleID }
    public let bundleID: String
    public let nom: String
    public let etat: Etat
    /// Information secondaire, discrète : ce que le verdict de régissabilité veut dire pour
    /// l'utilisateur, en clair. Jamais affichée dans le libellé principal.
    public let detail: String
}

extension SupportStatus {
    /// La conséquence visible du verdict, plutôt que le verdict lui-même. `rawValue` reste le
    /// vocabulaire interne (logs, tests) ; c'est cette phrase-là que le menu montre.
    public var consequencePourUtilisateur: String {
        switch self {
        case .testing: return texte("menu.detail.testing")
        case .supported: return texte("menu.detail.instant")
        case .unsupported: return texte("menu.detail.relaunch")
        }
    }
}

/// Assemble les lignes du menu à partir des apps détectées et du catalogue.
///
/// Fonction pure et non isolée : c'est ce qui la rend testable sans `WindowManager`, donc sans
/// scan de fenêtres ni vraies apps.
///
/// - `apps` : ce que la découverte voit à l'écran, avec leur verdict.
/// - `installees` : le catalogue, c'est-à-dire les apps de notch présentes sur le disque, lancées
///   ou non. Une app du catalogue absente de `apps` est arrêtée — elle est listée quand même,
///   puisque c'est elle qu'on relancera.
/// - `active` : bundleID de celle qui occupe le notch, `nil` si aucune.
/// - `enCoursDeBascule` : bundleID de celle dont la bascule est en cours, `nil` sinon.
///
/// Trié par nom, comme le catalogue : l'ordre du menu ne doit pas dépendre de l'ordre de
/// découverte, qui change à chaque scan.
public func construireEntreesMenu(
    apps: [NotchAppInfo],
    installees: [AppInstallee],
    active: String?,
    enCoursDeBascule: String?
) -> [EntreeMenu] {
    func etat(_ bundleID: String) -> EntreeMenu.Etat {
        if bundleID == enCoursDeBascule { return .enCours }
        return bundleID == active ? .active : .inactive
    }

    let appsParID = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
    let nomsCatalogue = Dictionary(installees.map { ($0.bundleID, $0.nom) }, uniquingKeysWith: { first, _ in first })

    var bundleIDsTraites = Set<String>()
    var entrees: [EntreeMenu] = []

    // Le catalogue est la source de vérité pour le nom canonique et l'ordre des apps installées
    for installee in installees {
        bundleIDsTraites.insert(installee.bundleID)
        let app = appsParID[installee.bundleID]
        let lancee = app?.estLancee ?? false
        entrees.append(
            EntreeMenu(
                bundleID: installee.bundleID,
                nom: installee.nom,
                etat: etat(installee.bundleID),
                detail: lancee
                    ? app!.support.consequencePourUtilisateur
                    : texte("menu.detail.notRunning")
            )
        )
    }

    // Apps observées en cours d'exécution qui ne figureraient pas dans le catalogue
    for app in apps where !bundleIDsTraites.contains(app.bundleID) {
        bundleIDsTraites.insert(app.bundleID)
        let nom = nomsCatalogue[app.bundleID] ?? app.name
        entrees.append(
            EntreeMenu(
                bundleID: app.bundleID,
                nom: nom,
                etat: etat(app.bundleID),
                detail: app.estLancee
                    ? app.support.consequencePourUtilisateur
                    : texte("menu.detail.notRunning")
            )
        )
    }

    return entrees.sorted {
        let cmp = $0.nom.localizedStandardCompare($1.nom)
        return cmp == .orderedSame ? $0.bundleID < $1.bundleID : cmp == .orderedAscending
    }
}
