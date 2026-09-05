//
// RaccourciGlobalController.swift — enregistre le raccourci global auprès du WindowServer et le
// rebranche à chaque fois que l'utilisateur en change.
//
// Le raisonnement sur le CHOIX de l'API (Carbon plutôt qu'un moniteur `NSEvent` ou un `CGEvent`
// tap) est écrit une seule fois, là où vit la donnée : `BouncerCore/RaccourciGlobal.swift`. Ici
// on n'a que la mécanique.
//
// COMMENT CETTE CHAÎNE A ÉTÉ VÉRIFIÉE, et ce qui reste à vérifier à la main. Un test unitaire ne
// peut rien prouver ici : il tourne sans `NSApplication` et sans run loop Carbon. La chaîne a
// donc été mesurée sur le bundle installé, le 2026-09-05, et deux faits en sont sortis :
//
//   · un `CGEvent` synthétisé par un AUTRE processus ne déclenche JAMAIS un hotkey Carbon —
//     mesuré dans les deux sens : un spike qui s'envoie la frappe à lui-même voit son handler
//     partir, le même spike ne voit rien quand la frappe vient d'un shell voisin. C'est le
//     cousin du piège déjà connu du dépôt sur les moniteurs `NSEvent` : un harnais de test ne
//     peut pas jouer la frappe à la place de l'utilisateur ;
//   · en postant depuis Bouncer lui-même, la chaîne complète part : `RegisterEventHotKey` rend
//     `noErr` dès le lancement, le handler est appelé, et le marqueur `●` du menu passe à l'app
//     suivante. C'est ce qui a mis au jour le piège `@StateObject` documenté dans App.swift.
//
// Ce que la suite de tests verrouille, c'est la table des combinaisons et la persistance du
// réglage. La frappe physique appartient à la vérification humaine.
//

import AppKit
import Carbon.HIToolbox
import Combine
import BouncerCore

/// Le raccourci global, du réglage jusqu'au WindowServer.
///
/// `ObservableObject` pour une seule raison : `erreur`. Une combinaison déjà prise par une autre
/// app est refusée par `RegisterEventHotKey`, et un raccourci qu'on choisit sans que rien ne se
/// passe est pire que pas de raccourci — la fenêtre de réglages doit pouvoir le dire.
@MainActor
final class RaccourciGlobalController: ObservableObject {
    /// Non nil quand la combinaison choisie n'a pas pu être enregistrée. Texte destiné à l'écran.
    @Published private(set) var erreur: String?

    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var abonnement: AnyCancellable?

    /// Signature à quatre caractères ('BNCR') : c'est ce qui distingue NOTRE hotkey de ceux des
    /// autres composants du processus si un jour il y en a d'autres.
    private static let signature = OSType(0x424E4352)

    init(reglages: Reglages, action: @escaping () -> Void) {
        self.action = action
        installerHandler()
        // Un seul chemin vers `appliquer`, l'abonnement — et pas un appel direct doublé d'un
        // abonnement : le publisher d'un `@Published` émet la valeur COURANTE dès qu'on s'y
        // abonne, donc le raccourci est enregistré ici même, avant que `init` ne rende la main.
        // Le réglage se réapplique ensuite à chaud : un raccourci qui n'existerait qu'au
        // relancement suivant serait un réglage qu'on croit cassé.
        abonnement = reglages.$raccourciGlobal.sink { [weak self] nouveau in
            // `sink` sur un `@Published` tire AVANT que la propriété soit à jour — d'où la
            // valeur transmise plutôt qu'une relecture de `reglages.raccourciGlobal`.
            MainActor.assumeIsolated { self?.appliquer(nouveau) }
        }
    }

    deinit {
        // Pas de `MainActor.assumeIsolated` dans un `deinit` : il peut tourner sur n'importe quel
        // thread. Les deux appels Carbon sont sûrs hors du main thread, et le contrôleur vit de
        // toute façon aussi longtemps que l'app.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    // MARK: - Enregistrement

    /// Le handler s'installe UNE fois, pour la vie du contrôleur, et pas à chaque changement de
    /// combinaison : `InstallEventHandler` s'empile, et réinstaller à chaque coup de picker
    /// ferait basculer le cycle autant de fois que l'utilisateur a tâtonné.
    private func installerHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controleur = Unmanaged<RaccourciGlobalController>
                    .fromOpaque(userData).takeUnretainedValue()
                // Les handlers Carbon sont appelés depuis la run loop principale : l'isolation
                // est réelle, `assumeIsolated` ne fait que la déclarer au compilateur.
                MainActor.assumeIsolated { controleur.action() }
                return noErr
            },
            1, &spec,
            // `passUnretained` : le contrôleur est retenu par `BouncerApp`, et le retenir ici
            // aussi le rendrait immortel — le `deinit` qui désenregistre ne tournerait jamais.
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    /// Bascule sur `raccourci` : l'ancien est toujours retiré d'abord, y compris quand
    /// l'enregistrement du nouveau échoue. Garder les deux serait le seul état vraiment
    /// indéfendable — l'utilisateur verrait la combinaison qu'il vient d'abandonner marcher
    /// encore.
    private func appliquer(_ raccourci: RaccourciGlobal) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        erreur = nil

        guard let keyCode = raccourci.keyCode else { return }

        var ref: EventHotKeyRef?
        let statut = RegisterEventHotKey(
            keyCode, raccourci.modificateursCarbon,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(), 0, &ref
        )
        if statut == noErr, let ref {
            hotKey = ref
        } else {
            // Le système ne dit pas POURQUOI il refuse. La collision est la cause de très loin
            // la plus probable, et c'est la seule sur laquelle l'utilisateur peut agir : le
            // message la donne comme hypothèse, pas comme diagnostic.
            erreur = "\(raccourci.libelle) est refusé par le système, sans doute déjà pris par une autre app. Choisissez-en un autre."
        }
    }
}
