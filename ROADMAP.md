# Roadmap & Plan d'Exécution — Bouncer

## Milestone 0 : Spike de Faisabilité (Validation Technique) - [ ] Créer un script autonome Swift (`Spike.swift`) sans interface graphique. - [ ] Vérifier et demander les droits Accessibilité. - [ ] Scanner et lister les fenêtres situées dans la zone du notch. - [ ] Tester le masquage puis le réaffichage d'une application d'encoche ouverte (ex: Boring Notch ou Vibe Island). - [ ] Valider le temps de réponse et la fluidité de `AXHidden`.

## Milestone 1 : Structure de l'App & Manager d'Encoche - [ ] Initialiser le projet Xcode en mode menu bar (`LSUIElement = true`). - [ ] Mettre en place `WindowManager.swift` avec rafraîchissement périodique ou événementiel des fenêtres d'encoche. - [ ] Créer le menu bar SwiftUI avec la liste des apps détectées et un switch manuel (clic). 

## Milestone 2 : Overlay & Gestes Trackpad - [ ] Implémenter le `NSPanel` overlay aligné précisément sur le notch hardware. - [ ] Ajouter la détection du swipe 2 doigts horizontal (`scrollWheel`). - [ ] Ajouter l'UI des flèches discrètes apparaissant au hover de la souris. - [ ] Lier les gestes au `WindowManager` pour un cycle fluide (App 1 -> App 2 -> App 1). ## 

Milestone 3 : Onboarding & Distribution - [x] Créer une fenêtre de bienvenue expliquant l'activation de la permission Accessibilité. - [x] Ajouter un écran de préférences (mode d'activation, géométrie des flèches, exclusion d'applications). - [ ] Configurer la signature Developer ID et le workflow de notarisation `notarytool`. - [ ] Préparer le script de génération du `.dmg` pour la landing page.