//
// Swipe.swift — décision « ce geste est-il un swipe, et vers où ? », isolée d'AppKit.
//
// Extraite de `NotchOverlay.handleScroll`, où elle n'était rejouable qu'avec un vrai trackpad et
// un vrai œil. Ici elle se teste sur un flux d'événements enregistré (cf. `SwipeTests`).
//
// MESURÉ le 2026-09-03, en capturant un geste complet à travers le même monitor global que
// l'app (86 événements, curseur dans la bande d'encoche) : 14 événements de geste (Σ deltaX = -77)
// puis 72 événements d'INERTIE étalés sur 1,32 s (Σ deltaX = -128). L'ancienne règle — accumuler
// tout ce qui passe, seuil 12, fenêtre de repos 0,5 s — produisait DEUX bascules pour UN geste :
// la première à +0,025 s (le geste), la seconde à +0,622 s (l'inertie, qui reprend 122 ms après
// l'expiration de la fenêtre de repos). Et le seuil n'était pas le levier : 6, 8, 12 et 20
// donnent tous deux bascules ; seul un seuil absurde (40) en donnait une, par accident.
// D'où la règle ci-dessous, qui raisonne en GESTES PHYSIQUES et non en distance cumulée.
//

import Foundation

/// Un événement de défilement, réduit à ce dont la décision a besoin.
public struct EvenementDefilement {
    /// Phase du geste physique. `aucune` = périphérique qui n'en rapporte pas (molette classique).
    public enum Phase { case aucune, debut, encours, fin }

    public let phase: Phase
    /// L'événement appartient à la traîne d'inertie, pas au geste : les doigts ont quitté la surface.
    public let inertie: Bool
    public let deltaX: CGFloat
    public let deltaY: CGFloat
    public let instant: TimeInterval
    public let dansLaZone: Bool

    public init(phase: Phase, inertie: Bool, deltaX: CGFloat, deltaY: CGFloat,
                instant: TimeInterval, dansLaZone: Bool) {
        self.phase = phase
        self.inertie = inertie
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.instant = instant
        self.dansLaZone = dansLaZone
    }
}

/// Un geste physique -> au plus une bascule.
public struct DetecteurSwipe {
    public enum Decision: Equatable { case rien, bascule(versLaSuite: Bool) }

    /// Distance horizontale au-delà de laquelle l'intention est acquise. Bas de plafond assumé :
    /// ce qui empêchait de le baisser était la rafale d'événements d'un même geste, que la
    /// détente par geste (`arme`) supprime. La dominance horizontale, elle, écarte le vrai
    /// faux positif — un défilement vertical qui dérive de quelques points sur le côté.
    private let seuil: CGFloat
    /// Uniquement pour les périphériques sans phase (molette) : sans frontière de geste à
    /// latcher, la fenêtre de temps reste le seul anti-rebond disponible.
    private let repos: TimeInterval

    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var arme = true
    private var reposJusqua: TimeInterval = -.greatestFiniteMagnitude

    public init(seuil: CGFloat = 6, repos: TimeInterval = 0.5) {
        self.seuil = seuil
        self.repos = repos
    }

    /// Curseur sorti de la zone : le geste en cours ne compte plus.
    public mutating func reinitialise() {
        accX = 0
        accY = 0
    }

    public mutating func recoit(_ e: EvenementDefilement) -> Decision {
        // L'inertie n'est pas un geste. C'est la cause mesurée du double déclenchement.
        guard !e.inertie else { return .rien }

        switch e.phase {
        case .debut:
            accX = 0
            accY = 0
            arme = true
            return .rien
        case .fin:
            // Fin de geste : ce qui n'a pas atteint le seuil ne s'ajoute pas au geste suivant.
            accX = 0
            accY = 0
            return .rien
        case .aucune:
            guard e.instant >= reposJusqua else { return .rien }
        case .encours:
            guard arme else { return .rien }
        }

        guard e.dansLaZone else { return .rien }
        accX += e.deltaX
        accY += e.deltaY
        guard abs(accX) >= seuil, abs(accX) > abs(accY) else { return .rien }

        // Vers la gauche (deltaX négatif) -> app suivante ; vers la droite -> précédente.
        let versLaSuite = accX < 0
        accX = 0
        accY = 0
        if case .aucune = e.phase {
            reposJusqua = e.instant + repos
        } else {
            arme = false
        }
        return .bascule(versLaSuite: versLaSuite)
    }
}

/// Opacité des flèches en fonction de la distance du curseur à la zone : pleine dedans, nulle
/// au-delà de `portee`, rampe linéaire entre les deux — les flèches se révèlent À L'APPROCHE,
/// avant que le curseur soit dans la bande. La rampe suit la main, elle n'est pas minutée : une
/// animation de durée fixe se battrait contre le mouvement au lieu de l'accompagner.
public func opaciteFleches(curseur: CGPoint, zone: CGRect, portee: CGFloat) -> CGFloat {
    guard portee > 0 else { return zone.contains(curseur) ? 1 : 0 }
    let dx = max(zone.minX - curseur.x, 0, curseur.x - zone.maxX)
    let dy = max(zone.minY - curseur.y, 0, curseur.y - zone.maxY)
    let distance = hypot(dx, dy)
    guard distance > 0 else { return 1 }
    return max(0, 1 - distance / portee)
}
