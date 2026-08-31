//
// Cycle.swift — calcul du prochain élément d'un cycle circulaire.
//
// Extrait de `WindowManager.cycle(forward:)`, où il était noyé dans les effets de bord
// (masquage, réaffichage). Isolé ici, il est testable sans toucher à une seule vraie app.

/// Élément suivant (`forward: true`) ou précédent d'un cycle circulaire.
/// - `nil` si la liste est vide.
/// - Le premier élément si `courant` est absent de la liste (ou nil) : point de départ par défaut.
public func prochaineCible<T: Equatable>(dans liste: [T], depuis courant: T?, forward: Bool) -> T? {
    guard !liste.isEmpty else { return nil }
    guard let courant, let idx = liste.firstIndex(of: courant) else { return liste.first }
    let n = liste.count
    return liste[forward ? (idx + 1) % n : (idx - 1 + n) % n]
}
