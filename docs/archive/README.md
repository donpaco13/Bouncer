# Archive technique et historique de Bouncer

Ce dossier rassemble les scripts exploratoires et les documents de conception initiaux du projet.
Ils sont conservés pour garder la trace des mesures réelles sur l'API Accessibilité et l'historique des choix d'architecture.

### `Spike.swift`
Script autonome écrit au tout début du projet pour tester la détection géométrique de l'encoche et le masquage de fenêtres sans SwiftUI.
Il a mis en évidence le fait que l'encoche n'est pas toujours sur `NSScreen.main` (cas d'un écran externe sans encoche en écran principal).
Gardé comme outil minimal de validation en ligne de commande autonome.

### `AXProbe.swift`
Script d'inspection en profondeur des arbres Accessibility (`AXUIElement`) sur les fenêtres tierces, exécuté contre de vraies apps.
Il teste les attributs modifiables un par un et mesure leur effet réel via `CGWindowList` plutôt que de faire confiance aux codes de retour.
Gardé pour son outillage de diagnostic précis sur le comportement interne des fenêtres d'encoche récalcitrantes.

### `SPIKE_RESULTS.md`
Rapport de mesures du Milestone 0 détaillant les temps de réponse de masquage (31,7 ms sur Vibe Island) et les échecs silencieux sur boringNotch.
Il documente pourquoi `kAXHiddenAttribute` renvoie un faux succès sur les fenêtres épinglées dans un Space privé du WindowServer (`CGSAddWindowsToSpaces`).
Gardé comme référence empirique fondamentale pour toutes les décisions d'architecture de Bouncer.

### `PRD.md`
Document de cadrage produit initial rédigé au lancement du projet.
Il posait la vision d'origine : un utilitaire en barre des menus évitant les superpositions d'apps sous l'encoche matérielle des MacBook.
Gardé pour documenter les intentions produit initiales et les cas d'usage visés.

### `TECH_SPEC.md`
Spécification technique initiale décrivant l'architecture en deux blocs : `WindowManager` et `NotchOverlayView`.
Elle prévoyait un algorithme de switch basé uniquement sur `AXHidden` et un canal de distribution notarizé Developer ID.
Gardée comme témoin de l'architecture préliminaire avant la découverte des limites d'Accessibilité et la bascule par cycle de vie.

### `ROADMAP.md`
Feuille de route initiale découpée en quatre jalons (Milestones 0 à 3) du spike initial jusqu'à la distribution.
Elle servait de plan de développement pour les premiers agents ayant posé les fondations du projet.
Gardée pour retracer la séquence de construction initiale du dépôt.
