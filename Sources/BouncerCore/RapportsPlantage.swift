//
// RapportsPlantage.swift — quand Sentry démarre et quand il s'arrête.
//
// La décision vit ici, dans BouncerCore, et pas à côté de `SentrySDK` dans la target de l'app :
// c'est la seule façon de la tester (une target exécutable n'est pas importable). L'app passe
// les deux gestes concrets — `SentrySDK.start` et `SentrySDK.close` — en fermetures.
//
// Le défaut est coupé (cf. `Reglages.rapportsPlantage`) : au lancement, tant que l'utilisateur
// n'a rien coché, `demarrer` n'est jamais appelé, donc aucun appel réseau.

import Combine

public final class PiloteRapportsPlantage {
    private var demarre = false
    private var abonnement: AnyCancellable?

    public init(reglages: Reglages, demarrer: @escaping () -> Void, arreter: @escaping () -> Void) {
        // `$rapportsPlantage` émet la valeur courante à l'abonnement, puis chaque changement.
        // L'état `demarre` filtre le premier `false` : arrêter un SDK jamais démarré n'a pas de sens.
        abonnement = reglages.$rapportsPlantage.sink { [unowned self] actif in
            guard actif != demarre else { return }
            demarre = actif
            actif ? demarrer() : arreter()
        }
    }
}
