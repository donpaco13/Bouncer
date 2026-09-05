# Audit de cohérence — Bouncer après dix agents

5 septembre 2026.
Bilan de cohérence globale du dépôt Bouncer suite aux chantiers menés en parallèle par dix agents (~3 000 lignes de Swift ajoutées, 70 tests unitaires verts).

---

## 1. Verdict d'ensemble

Le moteur fonctionne et tient ses invariants fondamentaux. La bascule « allumer la suivante avant d'éteindre l'actuelle » est respectée, le filtrage géométrique est strict, l'overlay ne vole pas le focus et les 70 tests passent en 33 ms.

En revanche, l'absence de synchronisation directe entre dix agents a laissé des anomalies concrètes dans le dépôt :
- Quatre commentaires mentent directement sur le code en production.
- Le guide d'accueil contient un bouton de simulateur dont le comportement contredit la commande réelle de l'overlay (flèche gauche inversée).
- Deux représentations graphiques de l'encoche utilisent des largeurs matérielles divergentes (130 pt contre 166 pt).
- Le Cask Homebrew est désynchronisé : son inventaire UserDefaults ne recense que 2 clés sur 7 et mentionne une clé supprimée, tandis que son sha256 correspond à un commit antérieur.
- L'orchestrateur central `WindowManager` a 0 test unitaire direct malgré son découpage injectable.

---

## 2. Commentaires devenus faux

Ce dépôt documente les décisions avec des mesures réelles. Plusieurs commentaires affirment désormais le contraire du code en place.

### 2.1 Ouverture de la fenêtre de réglages
Dans `Sources/Bouncer/FenetreReglages.swift` (l. 9-10) :
> `SettingsLink (macOS 14) est la seule façon de l'ouvrir depuis un MenuBarExtra : un NSApp.sendAction(showSettingsWindow:) marche par accident et casse d'une version à l'autre.`

**Réalité :** `MenuBarContentView.swift` (l. 60-91) a démontré empiriquement que `SettingsLink` disparaissait du menu après le premier lancement. L'entrée utilise désormais un simple bouton qui déclenche l'action associée au raccourci clavier `⌘,`. Le commentaire de `FenetreReglages.swift` contredit frontalement la solution retenue dans `MenuBarContentView.swift`.

### 2.2 Migration des tests XCTest
Dans `Tests/BouncerTests/CatalogueTests.swift` (l. 5-7) et `Tests/BouncerTests/BasculeTests.swift` (l. 5-7) :
> `Swift Testing, alors que CycleTests et ModeleTests (tasks 0 et 1) sont en XCTest : les deux cohabitent dans une même cible sans friction...`

**Réalité :** `CycleTests.swift` et `ModeleTests.swift` ont été convertis à Swift Testing au commit `f8896be`. La suite de tests ne contient plus aucune ligne de code XCTest.

### 2.3 Inventaire UserDefaults dans le Cask Homebrew
Dans `Casks/bouncer.rb` (l. 29-32) :
> `Bouncer n'écrit que dans UserDefaults, jamais sur disque en direct : deux clés, bouncer.bundleIDsApprises (CatalogueApps.swift) et bouncer.accueilVu (FenetreAccueil.swift). Elles vivent toutes les deux dans ce seul plist.`

**Réalité :**
1. La clé `bouncer.bundleIDsApprises` est obsolète et purgée au démarrage par `CatalogueApps.init()`. La clé active est `bouncer.bundleIDsApprises.v2`.
2. Le chantier des préférences (T130) a introduit cinq nouvelles clés : `bouncer.modeActivation`, `bouncer.porteeApproche`, `bouncer.margeLaterale`, `bouncer.intervalleRafraichissement`, `bouncer.bundleIDsExclus`. Bouncer écrit 7 clés actives, pas 2.

### 2.4 Ancien nom du projet dans l'overlay
Dans `Sources/Bouncer/NotchOverlay.swift` (l. 16-17) :
> `Hors survol, aucune fenêtre d'Island Switch ne recouvre l'encoche...`

**Réalité :** Le projet s'appelle Bouncer. « Island Switch » était le nom de travail initial conservé par le dossier parent.

### 2.5 Fréquence d'évaluation du catalogue
Dans `Sources/BouncerCore/WindowManager.swift` (l. 496-499) :
> `ses deux appelants sont rares : le corps du menu n'est évalué que menu ouvert, et cyclableApps à chaque cran de swipe...`

**Réalité :** `entreesMenu` est aussi interrogé à chaque rafraîchissement de `VueAccueil` (`FenetreAccueil.swift:101`) et dans l'onglet des applications des réglages (`FenetreReglages.swift:296`).

---

## 3. Duplications et contradictions de parallélisme

### 3.1 Inversion de la flèche gauche dans le guide d'accueil
- **Comportement produit (`NotchOverlay.swift:278-294`, `Swipe.swift:47-48`) :**
  La flèche gauche (`chevron.left`) passe `forward: false` et recule dans le cycle d'applications. La règle explicite du projet est que les flèches physiques conservent leur direction visuelle.
- **Simulateur du guide (`FenetreAccueil.swift:540-555`, l. 693-709) :**
  Le bouton gauche porte l'accessibilité `Flèche gauche : faire avancer le cycle` et appelle `basculer(vers: "gauche")` qui incrémente `indexActif = (indexActif + 1) % apps.count`. Le guide d'accueil enseigne donc le contraire du fonctionnement de l'overlay.

### 3.2 Largeur de boîtier caméra divergente dans l'interface
- `FenetreReglages.swift:228` fixe `largeurBoitier = 166` pt, valeur mesurée sur le matériel cible.
- `FenetreAccueil.swift:527, 539` dessine l'encoche avec `width: 130` pt et un espacement de flèches `spacing: 142` pt.
Deux agents ont modélisé l'encoche sans partager la même constante de géométrie.

### 3.3 Doublon de gestion de la touche Échap
Dans `FenetreAccueil.swift` :
1. `FenetreAccueilWindow:31-35` surcharge `cancelOperation:` pour appeler `performClose:`.
2. `VueAccueil:332-336` installe un bouton invisible interceptant `.keyboardShortcut(.cancelAction)` (la touche Échap en SwiftUI).
L'interception d'Échap est implémentée deux fois au même endroit.

### 3.4 Divergence des bundleIDs de test pour boringNotch
- Dans le catalogue réel (`CatalogueApps.swift:31`) et les tests de réglages (`ReglagesTests.swift:102`) : `theboringteam.boringnotch`.
- Dans les tests de bascule (`BasculeTests.swift:114, 205`) et de robustesse (`RobustesseTests.swift:19`) : `com.thecoolbeans.boringnotch`.
Les doubles de tests utilisent un identifiant temporaire issu des spécifications préparatoires au lieu du bundle ID réel.

---

## 4. Code mort et constantes décalées

1. **Taille de flèche dans les tests géométriques :**
   Dans `Tests/BouncerTests/ZoneSurvolTests.swift` (l. 15), le test utilise `taille: CGFloat = 14`. Dans `Sources/Bouncer/NotchOverlay.swift` (l. 335), la taille réelle a été portée à 22 pt pour des raisons de contraste. La formule reste valide, mais le test ne valide plus la dimension de production.
2. **Halo d'approche dans l'aperçu des réglages :**
   `FenetreReglages.swift:246` dessine un gradient horizontal censé représenter la portée d'approche. L'overlay réel n'utilise aucun halo lumineux, mais une pastille sombre opaque sous le chevron.

---

## 5. Cohérence de nommage et vocabulaire

La logique ajoutée dans `BouncerCore` est entièrement en français (`zoneSurvol`, `estFenetreEncoche`, `porteeApproche`, `prochaineCible`, `construireEntreesMenu`).

Des îlots d'anglais subsistent dans les structures historiques :
- `NotchAppInfo` (`WindowManager.swift:30-39`) mélange `name`, `support` et `isHiddenByUs` avec `estLancee`. En comparaison, `AppInstallee` et `EntreeMenu` utilisent `nom`.
- `WindowManager` expose `notchZone()` alors que la fonction de calcul dans `ControleurApps` se nomme `zoneEncoche()`.
- `NotchOverlayController` conserve des méthodes d'action en anglais (`updateHover`, `handleScroll`, `buildPanel`, `teardownPanel`) à côté de méthodes en français (`curseurDansLaZone`, `majMoniteurScroll`).
- `FenetreAccueil` utilise `SimulateurNotchInteractif` et `EncochePhysiqueShape` (alternance entre « Notch » et « Encoche »).

---

## 6. Respect des conventions du projet

| Convention | Statut | Constat |
|---|---|---|
| **Logique dans `BouncerCore`, pas dans la vue** | Conforme | Calculs, persistance, machines à états et filtrages sont tous isolés dans `BouncerCore`. Les vues ne font que lier l'état. |
| **Tests en Swift Testing** | Conforme | 70 tests répartis sur 11 fichiers, tous sous Swift Testing (`@Test`, `#expect`). |
| **Clés UserDefaults préfixées `bouncer.`** | Conforme | Les 8 clés existantes (`bundleIDsApprises.v2`, `accueilVu`, `modeActivation`, `porteeApproche`, `margeLaterale`, `intervalleRafraichissement`, `bundleIDsExclus`, ainsi que l'ancienne `bundleIDsApprises` lors de sa purge) utilisent le préfixe. |
| **Zéro hardcoding d'encoche** | Partiellement conforme | Respecté dans le moteur (`zoneEncoche()` interroge les écrans). Enfreint dans les vues pour les simulateurs statiques (166 pt dans Réglages, 130 pt dans Accueil). |

---

## 7. Couverture de tests : les angles morts

Le projet compte 70 tests unitaires qui s'exécutent en 33 ms. Plusieurs composants critiques ne sont pourtant jamais instanciés par la suite de tests.

1. **`WindowManager` n'est testé dans aucune suite :**
   Bien que conçu pour l'injection de dépendances (`startTimer: false`, `catalogue`, `controleur`, `reglages`), aucun test n'instancie `WindowManager`. Les logiques suivantes ne sont jamais vérifiées unitairement :
   - Le verrou d'exclusion mutuelle `bundleIDEnCoursDeBascule` (protection contre les doubles clics ou doubles swipes pendant une bascule).
   - L'algorithme de choix de `bundleIDActive` (priorité donnée au cycle par rapport aux apps détectées).
   - Le maintien des applications masquées dans `apps` lors des rafraîchissements (`apps.removeAll { !$0.isHiddenByUs }`).
   - L'invalidation et la replanification du timer lors d'un changement de préférence.
   - La génération du message de révocation d'accessibilité (`signalerRevocation`).

2. **`CycleTests.swift` ne comporte qu'un seul test :**
   Le fichier ne teste que le cas nominal `a -> b` en avant. Aucun test ne vérifie :
   - Le cycle arrière (`forward: false`, cas de la flèche gauche `‹`).
   - Le rebouclage de fin de liste vers le début (`c -> a`).
   - Le rebouclage arrière de début de liste vers la fin (`a -> c`).
   - Un élément de départ absent de la liste ou `nil`.

3. **Événements Combine de `Reglages` :**
   Le publisher `changementsIntervalle` (qui transmet la nouvelle période de timer à `WindowManager`) n'a aucun test de transmission ou de déduplication.

4. **Porte d'entrée du premier lancement :**
   La condition d'affichage unique `FenetreAccueilController.afficherSiPremierLancement()` reposant sur `bouncer.accueilVu` n'est couverte par aucun test unitaire.
