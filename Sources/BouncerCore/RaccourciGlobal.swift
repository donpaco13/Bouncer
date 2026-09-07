//
// RaccourciGlobal.swift — le raccourci clavier qui fait tourner le cycle depuis n'importe où.
//
// POURQUOI CARBON, ET PAS AUTRE CHOSE. Trois voies existent sur macOS 14+, elles n'ont ni les
// mêmes exigences ni le même comportement, et le choix a été MESURÉ le 2026-09-05 plutôt que
// rappelé de mémoire (spike : registre + déclenchement réel, cf. le tableau ci-dessous).
//
//   1. `RegisterEventHotKey` (Carbon Event Manager) — RETENU.
//      Le raccourci est enregistré auprès du WindowServer, qui l'intercepte AVANT de router la
//      frappe vers l'app au premier plan. Deux conséquences qui décident tout :
//        · la frappe est CONSOMMÉE — elle n'atterrit pas dans le champ de texte où l'utilisateur
//          était en train d'écrire ;
//        · aucune autorisation TCC n'est demandée — ni Accessibilité, ni Surveillance de la
//          saisie. Bouncer a déjà l'Accessibilité, donc cet argument ne le sauve pas d'un refus ;
//          il le sauve d'un état où l'utilisateur RÉVOQUE l'Accessibilité et où le raccourci
//          continuerait quand même de marcher.
//      Mesuré : `RegisterEventHotKey` rend `noErr` et un ref valide depuis un binaire non
//      empaqueté, en politique `.accessory`, sans fenêtre — exactement la posture de Bouncer.
//
//   2. `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` — ÉCARTÉ, et pas pour la
//      permission. Un moniteur global est PASSIF par contrat Apple : il observe, il ne consomme
//      pas. ⌃⌥⌘B basculerait l'encoche ET taperait un « b » dans le document ouvert. C'est
//      disqualifiant avant même de parler d'autorisations.
//
//   3. `CGEvent.tapCreate` — ÉCARTÉ. Il sait consommer, mais il lit TOUTES les frappes de la
//      machine pour n'en vouloir qu'une : le coût en surface de confiance est sans rapport avec
//      ce qu'on gagne, et un tap se fait désactiver par le système au moindre retard.
//
//   4. La bibliothèque `KeyboardShortcuts` — non installée, et on n'ajoute pas une dépendance
//      pour ce que 80 lignes couvrent.
//
// EFFET DE BORD ASSUMÉ : un raccourci Carbon PRÉEMPTE la combinaison pour toute la machine. Si
// une autre app l'utilisait, elle ne la reçoit plus tant que Bouncer tourne. C'est précisément
// pour ça que la combinaison se choisit dans les réglages et que « Aucun » y figure : un
// raccourci imposé en dur serait un vol silencieux.
//

import Carbon.HIToolbox

/// Les combinaisons proposées, et rien d'autre.
///
/// ponytail: une liste fermée plutôt qu'un enregistreur de frappe (« appuyez sur la combinaison
/// souhaitée »). L'enregistreur est le bon geste à terme, mais il demande une `NSView` qui capte
/// le clavier, l'affichage des symboles de modificateurs, le rejet des combinaisons réservées par
/// le système — pour un réglage qu'on touche une fois. Le jour où la liste ne suffit plus, c'est
/// `RaccourciGlobalController` qui reste inchangé : il ne connaît qu'un `keyCode` et un masque.
///
/// Toutes les combinaisons proposées portent ⌃⌥⌘ : trois modificateurs, c'est ce qui rend la
/// collision improbable avec les raccourcis d'app, qui vivent presque tous sur ⌘ ou ⌥⌘.
public enum RaccourciGlobal: String, CaseIterable, Identifiable, Sendable {
    case aucun
    case ctrlOptCmdB
    case ctrlOptCmdN
    case ctrlOptCmdEspace

    public var id: String { rawValue }

    /// Le défaut du produit. B comme Bouncer, et la touche n'est associée à rien sous ⌃⌥⌘.
    public static let defaut: RaccourciGlobal = .ctrlOptCmdB

    /// Code de touche virtuel, ou `nil` pour « aucun raccourci ».
    public var keyCode: UInt32? {
        switch self {
        case .aucun: return nil
        case .ctrlOptCmdB: return UInt32(kVK_ANSI_B)
        case .ctrlOptCmdN: return UInt32(kVK_ANSI_N)
        case .ctrlOptCmdEspace: return UInt32(kVK_Space)
        }
    }

    /// Masque de modificateurs au format Carbon — PAS celui d'`NSEvent.ModifierFlags`, qui ne
    /// porte pas les mêmes bits. `RegisterEventHotKey` n'accepte que celui-ci.
    public var modificateursCarbon: UInt32 {
        self == .aucun ? 0 : UInt32(controlKey | optionKey | cmdKey)
    }

    /// Ce que l'utilisateur lit dans les réglages, avec les vrais symboles de la barre de menus.
    public var libelle: String {
        switch self {
        case .aucun: return texte("shortcut.none")
        case .ctrlOptCmdB: return "⌃⌥⌘B"
        case .ctrlOptCmdN: return "⌃⌥⌘N"
        case .ctrlOptCmdEspace: return texte("shortcut.ctrlOptCmdSpace")
        }
    }

    /// Les symboles ne se lisent pas au VoiceOver : la combinaison est redite en toutes lettres.
    public var libelleAccessible: String {
        switch self {
        case .aucun: return texte("shortcut.none.spoken")
        case .ctrlOptCmdB: return texte("shortcut.ctrlOptCmdB.spoken")
        case .ctrlOptCmdN: return texte("shortcut.ctrlOptCmdN.spoken")
        case .ctrlOptCmdEspace: return texte("shortcut.ctrlOptCmdSpace.spoken")
        }
    }
}
