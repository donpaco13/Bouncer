# Localisation — le socle, et la carte de ce qui reste

L'anglais est la langue source de Bouncer, le français sa traduction. Ce n'est pas une nuance de
process : ça veut dire que la phrase anglaise s'écrit comme un développeur macOS anglophone
l'écrirait, et que la française la suit. Le vocabulaire ne s'invente pas ici — il est fixé par
`landing/messages/en.json` et le `README.md`.

État au 7 septembre 2026, après la première passe.

---

## 1. Le mécanisme, et pourquoi celui-là

**`en.lproj/Localizable.strings` + `fr.lproj/Localizable.strings`**, dans
`Sources/BouncerCore/Resources/`, avec `defaultLocalization: "en"` au manifeste.

### Le String Catalog `.xcstrings` a été essayé et il ne marche pas ici

C'est la voie Apple depuis Xcode 15, et c'est celle qu'on aurait prise sans mesure. Mais le
`.xcstrings` doit être compilé par `xcstringstool`, qui appartient au système de construction
d'Xcode : `swift build` ne le connaît pas. Mesuré sur un package jumeau, `.process("Resources")`
sur un dossier ne contenant qu'un `.xcstrings` :

```
resourceURL:    …/Spike_Spike.bundle
localizations:  []
en ->           settings.title
```

Le fichier est recopié tel quel dans le bundle, `Bundle.module.localizations` rend une liste
vide, et **chaque clé revient telle quelle**. Rien ne casse, rien ne prévient : l'interface
affiche `menu.settings`. C'est le bug invisible, et un dépôt qui construit sans Xcode ne peut
donc pas s'en servir. Le jour où Bouncer passera par un projet Xcode, la migration
`.strings → .xcstrings` se fait par un import, sans toucher aux points d'appel.

Avec les `.lproj`, le même spike rend `["en", "fr"]` et résout les deux langues.

### Un seul catalogue, dans `BouncerCore`

`Bundle.module` est propre à une target. Deux catalogues voudraient dire deux bundles, deux
fichiers à tenir en parité, et la même phrase écrite deux fois. Le catalogue vit donc dans la
bibliothèque — que la target exécutable importe déjà — et `catalogueDeChaines` est l'unique
bundle des deux côtés.

### Le piège du packaging, trouvé et corrigé

L'accesseur `Bundle.module` que SwiftPM génère cherche à deux endroits :

```swift
let mainPath  = Bundle.main.bundleURL.appendingPathComponent("Bouncer_BouncerCore.bundle").path
let buildPath = "/Users/…/worktrees/…/.build/arm64-apple-macosx/release/Bouncer_BouncerCore.bundle"
```

`buildPath` est **un chemin absolu vers la machine qui a compilé**. Sur le Mac du développeur il
répond toujours ; chez l'utilisateur il n'existe pas, et l'accesseur fait un `fatalError` — au
premier menu ouvert. Un défaut qui ne peut structurellement pas se voir là où on le fabrique.

Deux corrections :

- `build.sh` copie `Bouncer_BouncerCore.bundle` dans `Bouncer.app/Contents/Resources/`. Il ne
  copiait que le binaire.
- `catalogueDeChaines` (`Localisation.swift`) cherche d'abord dans `Bundle.main.resourceURL`,
  et ne retombe sur `Bundle.module` que pour `swift test` et `swift run`. Passer par `mainPath`
  aurait voulu dire poser le bundle à la racine de `Bouncer.app`, hors de `Contents/`, où la
  signature de code ne l'accepte pas.

Vérifié `.build` déplacé, donc dans les conditions d'un poste qui n'a jamais compilé :

```
AppleLanguages=(en) -> Strings: en — Settings…
AppleLanguages=(fr) -> Strings: fr — Réglages…
AppleLanguages=(de) -> Strings: en — Settings…   ← repli sur la langue source
```

`Info.plist` déclare aussi `CFBundleDevelopmentRegion = en` et `CFBundleLocalizations = [en, fr]`.

### Le pluriel

Un seul dans toute l'app (`welcome.ready.appsFound`), et il vit dans un `.stringsdict` plutôt
qu'en ternaire Swift. Un `n == 1 ? … : …` code en dur qu'il existe deux formes plurielles : c'est
vrai en anglais et en français, faux en polonais (trois) et en arabe (six). Le `.stringsdict`
laisse la langue décider.

### Les points d'appel

```swift
texte("menu.settings")                              // une chaîne
texte("shortcut.refused", raccourci.libelle)        // une chaîne à trous, %1$@ numérotés
texteAuPluriel("welcome.ready.appsFound", n)        // un pluriel
```

`texteAuPluriel` est séparée exprès : une clé qui vit dans le `.stringsdict` et pas dans le
`.strings` ne se distingue pas autrement au point d'appel.

### Le filet

`Tests/BouncerTests/CatalogueDeChainesTests.swift`, 7 tests, qui lisent le **bundle construit**
et non les fichiers source — c'est la seule façon de prouver que SwiftPM les a compilés et posés
là où `Bundle.module` ira les chercher :

| Test | Ce qu'il attrape |
|---|---|
| `leBundlePorteLesDeuxLangues` | le cas `.xcstrings` : les fichiers sont là, aucune langue n'est reconnue |
| `lesDeuxLanguesPortentLesMemesCles` | une clé ajoutée d'un côté et oubliée de l'autre |
| `lesDeuxLanguesPortentLesMemesPluriels` | idem pour le `.stringsdict` |
| `aucuneValeurVide` | une valeur vide passe la parité des clés et fait un trou à l'écran |
| `lesTrousDeFormatSeCorrespondent` | une traduction qui perd un `%@` fait planter `String(format:)` |
| `texteNeRendJamaisLaCle` | la preuve de bout en bout, sur toutes les clés |
| `lePlurielEstResolu` | le `.stringsdict` absent du bundle |

Vérifié en les faisant échouer : clé française retirée → `clés sans traduction française :
["menu.refresh"]`. `%2$@` retiré côté français → `welcome.sim.app.label : trous ["%1$@", "%2$@"]
en anglais, ["%1$@"] en français`.

---

## 2. Ce qui est migré

Suite complète : **167 tests au vert**.

**63 clés** au catalogue plus un pluriel, pour **60 points d'appel** :

| Fichier | Points d'appel | Préfixe de clés |
|---|---|---|
| `Sources/Bouncer/FenetreAccueil.swift` | 31 | `welcome.*` |
| `Sources/Bouncer/MenuBarContentView.swift` | 9 | `menu.*` |
| `Sources/BouncerCore/PiedDePageAccueil.swift` | 8 | `welcome.button.*`, `welcome.pagination.*` |
| `Sources/BouncerCore/RaccourciGlobal.swift` | 6 | `shortcut.*` |
| `Sources/BouncerCore/EntreeMenu.swift` | 5 | `menu.detail.*` |
| `Sources/Bouncer/RaccourciGlobalController.swift` | 1 | `shortcut.refused` |

`Sources/Bouncer/main.swift` est passé en anglais **sans clés** : la sortie de `--self-test` est
une table de diagnostic qu'on lit dans un terminal, pas de l'interface. Le `README.md` la cite
déjà en anglais.

Une correction au passage : `MenuTests.swift` comparait deux détails de menu à leur phrase
française littérale. Ces tests-là échouaient sur une machine anglophone **avant** ce chantier ;
ils passent maintenant par `texte("menu.detail.notRunning")` et ne dépendent plus de la langue de
la machine qui les lance.

---

## 3. Ce qui reste — 92 chaînes, trois fichiers

Aucun de ces fichiers n'a été touché : quatre autres workers modifiaient le code Swift pendant
cette passe, et le découpage se fait par propriété de fichiers.

| Fichier | Chaînes | Pourquoi pas maintenant | Effort |
|---|---|---|---|
| `Sources/Bouncer/FenetreReglages.swift` | 55 | le worker « flèches propres » explore l'ajout d'une préférence | ~2 h, c'est la plus grosse surface anglaise du produit |
| `Sources/BouncerCore/WindowManager.swift` | 27 | détenu par le worker « détection trois apps » | ~1 h 30, ce sont les messages d'erreur, les plus délicats à écrire |
| `Sources/BouncerCore/Reglages.swift` | 10 | même worker que `FenetreReglages` (le modèle et sa vue vont ensemble) | ~30 min |

`FenetreReglages.swift` et `Reglages.swift` se migrent **ensemble** : le modèle porte les
libellés des modes (`Le swipe et les flèches`, `La fenêtre de l'app d'encoche`) et la vue les
affiche. Les séparer voudrait dire deux passes sur le même écran.

### Ces fichiers-là n'ont rien à migrer, vérifié

| Fichier | Ce que ses chaînes sont |
|---|---|
| `Sources/Bouncer/NotchOverlay.swift` | 30 chaînes, **toutes** des traces `TraceSwipe.note(...)`. Aucune étiquette d'accessibilité sur les chevrons — c'est un manque, pas une chaîne à traduire. |
| `Sources/BouncerCore/TraceSwipe.swift` | nom de variable d'environnement, chemin de log, formats |
| `Sources/BouncerCore/ControleurApps.swift` | `X`, `Y`, `Width`, `Height` — noms d'attributs AX |
| `Sources/BouncerCore/CatalogueApps.swift` | `Vibe Island`, `boringNotch` — noms propres |
| `Sources/Bouncer/App.swift` | `Bouncer`, `hourglass` — nom de l'app, symbole SF |


#### `Sources/Bouncer/FenetreReglages.swift` — 55 chaînes

- `:34` — Général
- `:36` — Geste
- `:38` — Applications
- `:59` — Lancer Bouncer à l'ouverture de session
- `:64` — Bouncer n'arbitre l'encoche que pendant qu'il tourne. Sans lancement automatique, il faut y penser à chaque démarrage.
- `:83` — Vérifier les apps toutes les
- `:88` — Fréquence à laquelle Bouncer regarde quelles apps occupent l'encoche et si l'autorisation d'Accessibilité a changé. Plus court : le menu se met à j…
- `:101` — 1 seconde
- `:101` — \(Int(intervalle)) secondes
- `:123` — macOS attend votre accord : ouvrez Réglages Système › Général › Ouverture et éléments autorisés, et activez Bouncer.
- `:141` — macOS a refusé : \(error.localizedDescription)
- `:155` — Faire tourner le cycle avec
- `:167` — Raccourci clavier
- `:168` — Raccourci
- `:178` — Fonctionne depuis n'importe quelle app, y compris plein écran. Tant que Bouncer tourne, la combinaison choisie n'atteint plus les autres apps.
- `:193` — Zone sensible
- `:194` — Bouncer se cale sur
- `:206` — Mesuré : le boîtier caméra fait 166 pt de large, une app d'encoche en fait 640 à 740 et descend jusqu'à 520 pt sous la barre. Calé sur le boîtier, …
- `:212` — Flèches
- `:217` — Apparition — \(libellePortee)
- `:219` — Au survol
- `:221` — De loin
- `:223` — Distance d'apparition des flèches
- `:224` — 0 point, uniquement dans la bande de l'encoche
- `:224` — \(Int(reglages.porteeApproche)) points
- `:226` — L'opacité des flèches suit la distance du curseur à l'encoche. Ce réglage dit où la montée commence.
- `:232` — Bandes latérales — \(Int(reglages.margeLaterale)) pt de chaque côté
- `:234` — Étroites
- `:236` — Larges
- `:238` — Largeur des bandes latérales des flèches
- `:239` — \(Int(reglages.margeLaterale)) points de chaque côté
- `:241` — Les flèches se logent de part et d'autre de ce qui couvre l'encoche, jamais dessus. Élargir donne une cible de clic plus facile ; réduire laisse la…
- `:247` — Déploiement — \(libelleRetrait)
- `:249` — Fondu seul
- `:251` — Ample
- `:253` — Amplitude du déploiement des flèches
- `:254` — \(Int(reglages.retraitFleches)) points
- `:254` — aucune, fondu seul
- `:256` — À l'approche, la flèche sort de derrière l'encoche en même temps qu'elle apparaît : un soupçon de loin, déployée de près. À zéro, elle se contente …
- `:269` — Rétablir les valeurs d'origine
- `:270` — Restaure la portée d'apparition et les marges à leurs valeurs d'origine
- `:279` — la flèche ne bouge pas
- `:280` — \(Int(reglages.retraitFleches)) pt de glissement
- `:285` — Uniquement dans la bande de l'encoche
- `:286` — \(Int(reglages.porteeApproche)) pt avant la bande
- `:359` — Aperçu : l'encoche seule, sans flèche — le mode choisi ne les affiche pas.
- `:361` — Aperçu : l'encoche, une bande de \(Int(reglages.margeLaterale)) points de chaque côté portant une flèche, et une zone d'approche de \(Int(reglages.…
- `:379` — Aucune app d'encoche détectée sur ce Mac. Elles apparaîtront ici dès que Bouncer en verra une.
- `:398` — Apps parcourues par le swipe et les flèches
- `:404` — Toutes les apps sont décochées : le geste n'a plus rien à parcourir. Le menu de la barre des menus, lui, continue de les lister.
- `:413` — Une app décochée reste dans le menu et reste cliquable — elle n'apparaît simplement plus dans le cycle. Utile pour une app d'encoche qu'on garde ou…
- `:426` — App non détectée sur ce Mac
- `:431` — Retirer
- `:437` — Exclusions orphelines
- `:439` — Ces apps ont été exclues précédemment mais ne sont plus détectées. Les retirer permet d'éviter qu'elles restent exclues si elles sont réinstallées …

#### `Sources/BouncerCore/WindowManager.swift` — 27 chaînes

- `:23` — Test en cours…
- `:24` — Régissable
- `:25` — Non supportée
- `:448` — , periodePosee))
- `:513` — L'accès à l'Accessibilité a été retiré à Bouncer : vous avez deux apps dans l'encoche, \(restee.name) est restée à côté de la nouvelle. Bouncer ne …
- `:518` — Vos apps ouvertes restent intactes : Bouncer ne touche à rien et ne quittera aucune app.
- `:519` — ) en arrière-plan : Bouncer ne touche à rien et ne quittera aucune app.
- `:520` — L'accès à l'Accessibilité a été retiré à Bouncer : les bascules ne fonctionnent plus. \(impactApps) Rendez-lui l'accès dans les Réglages Système po…
- `:557` — Aucune encoche détectée sur cette machine.
- `:675` — Aucune encoche détectée sur cette machine.
- `:796` — Bascule vers \(enCours.name) déjà en cours — patientez, elle vient de recevoir sa demande de fermeture. Un second geste maintenant éteindrait l'app…
- `:830` — \(restee.name) n'est pas encore fermée — elle attend probablement une réponse à l'écran (« Enregistrer les modifications ? »). Bouncer continue de …
- `:845` — \(cible.name) doit être relancée pour revenir dans l'encoche, et elle n'est pas encore fermée. Bouncer la relancera dès qu'elle sera partie
- `:846` — \(attente), puis rangera \($0.name) — qui reste à l'écran en attendant.
- `:849` — \(cible.name) n'a pas pu être lancée.
- `:861` — Bouncer n'a pas encore l'accès à l'Accessibilité : la bascule vers \(cible.name) est refusée. \(repliInchange(actuelle)) Bouncer ne touche à rien e…
- `:866` — Plus aucun écran à encoche détecté — la bascule vers \(cible.name) n'a pas été tentée. \(repliInchange(actuelle)) Rebranchez l'écran à encoche (ou …
- `:873` — Plus aucune encoche détectée — la bascule vers \(cible.name) a été abandonnée. \(repliInchange(actuelle))
- `:874` — \(cible.name) s'est lancée sans rien afficher dans l'encoche. \(repliInchange(actuelle))
- `:913` — \(precedente.name) n'est pas encore fermée — elle attend probablement une réponse à l'écran (« Enregistrer les modifications ? »). Bouncer continue…
- `:924` — \(app.name) s'est bien fermée, mais n'a pas pu être relancée — désinstallée, ou lancement refusé par le système.
- `:933` — Plus aucune encoche détectée — \(app.name) a bien été relancée, mais Bouncer ne peut plus vérifier ce qu'elle y affiche. Rebranchez l'écran à encoc…
- `:934` — \(app.name) s'est relancée sans rien afficher dans l'encoche.
- `:946` — L'encoche est inchangée.
- `:946` — \($0.name) reste en place.
- `:1055` — Aucune app d'encoche détectée. Lancez-en une pour que Bouncer l'apprenne.
- `:1056` — Toutes les apps d'encoche sont décochées dans les réglages.

#### `Sources/BouncerCore/Reglages.swift` — 10 chaînes

- `:46` — Le swipe et les flèches
- `:47` — Le swipe seul
- `:48` — Les flèches seules
- `:56` — Swipe horizontal à deux doigts sur l'encoche, ou clic sur une flèche.
- `:58` — Aucune flèche ne s'affiche. Rien ne recouvre jamais la barre des menus.
- `:60` — Le swipe est ignoré. Utile avec une souris, ou si le geste part tout seul.
- `:79` — La fenêtre de l'app d'encoche
- `:80` — Le boîtier caméra seul
- `:87` — Le swipe marche partout sur l'île qu'on voit, et les flèches se posent de part et d'autre. Sans app d'encoche à l'écran, revient au boîtier.
- `:89` — Zone étroite, collée à l'encoche matérielle. À essayer si un défilement horizontal déclenche une bascule sans l'avoir voulu.

---

## 4. Les décisions de vocabulaire

Prises en s'alignant sur `landing/messages/en.json`, qui porte 134 chaînes anglaises déjà
validées, plutôt qu'en traduisant le français.

| Français | Anglais | Pourquoi |
|---|---|---|
| Réglages… | Settings… | convention Apple depuis Ventura, jamais « Preferences » |
| Quitter | Quit Bouncer | l'entrée de menu macOS porte le nom de l'app |
| Guide de démarrage… | Welcome Guide… | capitalisation de menu macOS ; `en.json` dit « welcome guide » |
| occupe l'encoche | on stage | `commandes.menuActive` de la landing, mot pour mot |
| n'occupe pas l'encoche | waiting, one click brings it back | `commandes.menuAttente`, mot pour mot |
| bascule en cours | switching | `commandes.menuEnCours`, mot pour mot |
| Bascule instantanée | Instant switch | `compatibilite.basculeRapide` = « Instant » |
| Bascule par relance, environ 1 s | Switches by relaunch, about a second | `basculeRelance` + « about a second » de `moteur.note3` |
| Commencer / Continuer | Get Started / Continue | vocabulaire d'onboarding Apple |
| Cochez Bouncer dans la liste | Turn Bouncer on in the list | **pas** « Tick » ni « Check » : depuis Ventura, l'Accessibilité présente un interrupteur, pas une case |
| Écran 1 sur 5 | Step 1 of 5 | l'énumération s'appelle `EtapeAccueil` ; « Step » dit ce que c'est, « Screen » dit où c'est |
| Tout est en place | All set | l'impératif court, pas « Everything is in place » |
| ⌃⌥⌘Espace | ⌃⌥⌘Space | le symbole se traduit, il est lu au VoiceOver |

Les noms propres ne bougent jamais : `Vibe Island`, `Boring Notch`, `NotchNook`, `Now Playing`,
`Daft Punk — One More Time`.

---

## 5. Ajouter une chaîne

1. La clé et la phrase **anglaise** dans `Sources/BouncerCore/Resources/en.lproj/Localizable.strings`.
2. La même clé, la phrase française, dans `fr.lproj/Localizable.strings`.
3. Au point d'appel : `texte("la.cle")`.
4. `swift test --filter CatalogueDeChainesTests`. Sept tests, ils tiennent la parité.
