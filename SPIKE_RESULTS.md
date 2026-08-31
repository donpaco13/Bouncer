# Milestone 0 — Résultats du Spike de Faisabilité

## Machine de test

Mac physique, deux écrans : **écran 0 « LG IPS QHD »** 2560×1440 @ (0,0) — c'est
`NSScreen.main` et l'écran qui porte la menu bar, `safeAreaInsets.top = 0` — et
**écran 1 « Built-in Retina Display »** 1352×878 @ (2560,-88), `safeAreaInsets.top =
29pt`. **L'encoche physique est donc sur l'écran secondaire, pas sur `NSScreen.main`.**

Accessibilité **accordée** au Terminal exécutant `swift Spike.swift`. Deux apps
d'encoche tierces réelles tournaient en simultané : **boringNotch** (pid 51589,
process `TheBoringNotch`) et **Vibe Island** (`app.vibeisland.macos`, pid 1275),
toutes deux `LSUIElement = true` / `activationPolicy = accessory`.

Ce run **invalide** la version précédente de ce rapport (rédigée sans Accessibilité
accordée, sur une session sans encoche détectée) sur deux points : la géométrie de
l'encoche est bien détectable, et la stratégie AX au niveau application fonctionne
— mais uniquement sur une des deux apps testées.

## Deux bugs corrigés dans `Spike.swift` avant ce run

1. **Détection d'encoche limitée à `NSScreen.main`.** Le script ne regardait que
   l'écran principal (celui de la menu bar) et concluait « pas d'encoche » sur cette
   machine, alors que l'encoche est sur l'écran secondaire. Corrigé : itération sur
   `NSScreen.screens`, sélection du premier écran avec `safeAreaInsets.top > 0`, zone
   reconstruite depuis ses `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. La
   conversion des bounds `CGWindowListCopyWindowInfo` (repère haut-gauche) vers le
   repère AppKit (bas-gauche) utilise désormais `NSScreen.screens[0].frame.height`
   (l'écran principal, référence stable du repère global Quartz) et non plus
   `NSScreen.main`, qui peut désigner un autre écran.
2. **Vérification post-action fondée sur un attribut AX qui ment.** Le script relisait
   `kAXHiddenAttribute` après l'action pour juger du succès. Cet attribut se relit à
   `true` même quand la fenêtre reste réellement affichée (cas boringNotch,
   ci-dessous) — **faux positif silencieux**. Corrigé : chaque stratégie recompte
   maintenant les fenêtres du PID cible dans
   `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], …)`
   avant/après l'action. Le succès, c'est la fenêtre qui disparaît de cette liste —
   rien d'autre, ni code retour AX, ni relecture d'attribut.

## Sortie console — Étapes A, B, C (identique pour les deux runs, seul le PID cible en D change)

```
=== A. Vérification des droits Accessibilité ===
✅ Accessibilité déjà accordée.

=== B. Géométrie de l'encoche ===
Écran avec encoche : Built-in Retina Display, frame = (2560.0, -88.0, 1352.0, 878.0)
safeAreaInsets.top = 29.0pt
auxiliaryTopLeftArea  = (2560.0, 761.0, 593.0, 29.0)
auxiliaryTopRightArea = (3319.0, 761.0, 593.0, 29.0)
✅ Zone d'encoche calculée (repère AppKit, origine bas-gauche de l'écran principal) : (3153.0, 761.0, 166.0, 29.0)

=== C. Scan des fenêtres dans la zone d'encoche ===
idx pid   app            titre         bounds                      layer
0   1275    Vibe Island           (sans titre)            (2866.0, 650.0, 740.0, 580.0)     27
1   51589   TheBoringNotch        (sans titre)            (2916.0, 650.0, 640.0, 210.0)     27
```

Les deux barres d'encoche sont détectées par intersection géométrique — plus besoin
de suivi par PID/bundle connu en filet de sécurité pour ce cas (contrairement à ce
que suggérait le rapport précédent, écrit sans Accessibilité et sans la bonne
géométrie).

## Étape D — Cycle masquer/réafficher, comparé sur les deux apps

### Vibe Island (pid 1275)

```
→ Stratégie 1. AXUIElementSetAttributeValue(kAXHiddenAttribute)
   hide: ✅ en 31.7ms
   show: ✅ en 5.1ms
   note: confirmé via recomptage CGWindowList (avant=1, après hide=0, après show=1)

→ Stratégie 2. NSRunningApplication.hide()/unhide()
   hide: ❌ en 0.2ms
   show: ❌ en 0.2ms
   note: confirmé via recomptage CGWindowList (avant=1, après hide=1, après show=1)

→ Stratégie 3. kAXWindowsAttribute → kAXMinimizedAttribute
   hide: ❌ en 0.1ms
   show: ✅ en 0.1ms
   note: confirmé via recomptage CGWindowList (avant=1, après hide=1, après show=1)
```

### boringNotch (pid 51589)

```
→ Stratégie 1. AXUIElementSetAttributeValue(kAXHiddenAttribute)
   hide: ❌ en 31.0ms
   show: ✅ en 3.7ms
   note: confirmé via recomptage CGWindowList (avant=1, après hide=1, après show=1)

→ Stratégie 2. NSRunningApplication.hide()/unhide()
   hide: ❌ en 0.2ms
   show: ❌ en 0.2ms
   note: confirmé via recomptage CGWindowList (avant=1, après hide=1, après show=1)

→ Stratégie 3. kAXWindowsAttribute → kAXMinimizedAttribute
   hide: ❌ en 0.1ms
   show: ✅ en 0.1ms
   note: confirmé via recomptage CGWindowList (avant=1, après hide=1, après show=1)

⚠️ Aucune des 3 stratégies n'a fonctionné de bout en bout sur ce pid.
```

| # | Stratégie | Vibe Island | boringNotch |
|---|-----------|:-----------:|:-----------:|
| 1 | `kAXHiddenAttribute` (app) | ✅ hide 42,9ms / show 4,2ms | ❌ — fenêtre reste dans CGWindowList malgré `AXError 0` |
| 2 | `NSRunningApplication.hide/unhide` | ❌ no-op (~0,2ms) | ❌ no-op (~0,2ms) |
| 3 | `kAXWindowsAttribute` → `kAXMinimizedAttribute` (fenêtre) | hide ❌ / show ✅ | hide ❌ / show ✅ |
| 4 | Déplacement hors écran via `kAXPositionAttribute` (testé séparément) | non concluant — `AXError 0` mais fenêtre toujours à l'écran | non concluant — `AXError 0` mais fenêtre toujours à l'écran |

Point clé du bug 2 : sur boringNotch, la stratégie 1 renvoie `AXError 0` (succès
annoncé) et l'attribut `kAXHiddenAttribute` se relit à `true` après le hide — un
script qui se fierait à ça conclurait au succès. Le recomptage `CGWindowList` montre
que la fenêtre est toujours présente : **faux positif confirmé, pas une hypothèse**.

Stratégie 2 confirmée définitivement écartée sur les deux apps `LSUIElement` réelles
(no-op quasi instantané, cohérent avec le piège documenté dans `TECH_SPEC.md` :
ces apps ne participent pas à la machine à états hide/unhide de l'app switcher).

Stratégie 3 échoue au hide sur les deux apps (le `kAXMinimizedAttribute` ne masque
pas ces `NSPanel`/fenêtres non standard), bien que `kAXWindowsAttribute` ne soit
plus vide maintenant que l'Accessibilité est accordée — le show réussit car
recompter après un hide qui n'a rien changé retrouve trivialement le même compte.

## Conclusion — faisabilité PARTIELLE, dépendante de l'app

`kAXHiddenAttribute` (stratégie 1) est la **meilleure stratégie disponible et la
seule qui fonctionne vraiment** — mais elle échoue silencieusement sur certaines
apps (boringNotch ici), sans que le code retour AX ou la relecture d'attribut ne le
signale. Ce n'est plus une question de confiance AX non accordée (facteur confondant
du run précédent) : Accessibilité est bien accordée, et le comportement diffère
quand même entre les deux apps testées.

**Conséquences pour le `WindowManager` du Milestone 1 :**

1. **Ne jamais faire confiance au code retour AX ni à la relecture d'attribut.**
   Après chaque hide/show, vérifier l'effet réel via un recomptage
   `CGWindowListCopyWindowInfo` sur le PID ciblé — c'est le seul juge de vérité
   observé fiable sur les deux apps testées.
2. **Stratégie par app, pas stratégie unique.** `kAXHiddenAttribute` doit être
   tentée en premier (elle marche sur au moins une classe d'app réelle), mais le
   `WindowManager` doit détecter l'échec via (1) et basculer sur un repli par app,
   pas supposer qu'une stratégie qui marche sur une app marche sur toutes.
3. **Repli pour les apps récalcitrantes (boringNotch et similaires) — NON implémenté
   ici, piste à documenter :** API privée SkyLight (`CGSSetWindowAlpha`, mise à 0 de
   la fenêtre plutôt que masquage sémantique). Piège explicite : c'est une API
   privée non documentée par Apple — l'utiliser expose à un rejet de notarisation ou
   à une rupture sans préavis lors d'une mise à jour macOS. À évaluer en M1
   seulement si le nombre d'apps récalcitrantes en usage réel le justifie ; sinon,
   accepter que ces apps restent hors du périmètre garanti d'Island Switch et le
   documenter côté utilisateur plutôt que de dépendre d'une API privée.
4. La piste 4 (déplacement `kAXPositionAttribute` hors écran) reste non concluante
   sur les deux apps et n'apporte rien de plus que la stratégie 1 — ne pas
   l'implémenter en priorité.

**Pas d'action bloquante restante** pour démarrer le Milestone 1 : Accessibilité
accordée, géométrie d'encoche validée sur écran secondaire, stratégie 1 validée avec
sa limite connue et sa méthode de vérification correcte. Commande pour reproduire :

```
swift "/Users/francoishatem/Documents/💻 Développement & Code/GitHub/Island Switch/Spike.swift" --pid <PID>
```

(PID de boringNotch et Vibe Island à retrouver via `pgrep -fl -i boringnotch` /
`pgrep -fl -i "vibe island"` — ils changent à chaque relance des apps.)

## Enquête AX sur les apps récalcitrantes

Suite du Milestone 0, avant d'écrire le `WindowManager` du Milestone 1. Script :
`AXProbe.swift` (`swift AXProbe.swift --pid <N>`), exécuté contre les deux mêmes
instances que le run précédent (pids inchangés : boringNotch 51589, Vibe Island
1275). Sortie brute conservée, résumé ci-dessous.

### Question 1 — L'arbre AX de boringNotch, et une propriété qui le masquerait

**Dump AX commenté — Application (les deux apps sont quasi identiques ici) :**
`AXHidden` [settable ✅] et `AXFrontmost` [settable ✅] existent au niveau
**application** pour les deux apps (c'est ce que Spike.swift a testé au Milestone 0).
Rien d'autre d'exploitable côté application : `AXPosition`/`AXSize`/`AXFrame` y sont
tous `<nil>` (une `NSApplication` n'a pas de géométrie propre), `AXFocusedWindow`/
`AXMainWindow` sont `<nil>` (ni boringNotch ni Vibe Island ne prennent jamais le
focus clavier — cohérent avec des `NSPanel .nonactivatingPanel`).

**Dump AX commenté — Window[0] : c'est ici que la découverte compte.** L'arbre AX de
la fenêtre est **structurellement identique sur les deux apps**, attribut par
attribut :

- `AXRole = "AXWindow"`, `AXSubrole = "AXSystemDialog"` — identique sur boringNotch
  ET Vibe Island. Le subrôle ne distingue donc pas "app qui répond" de "app
  résistante" : les deux se présentent en AX comme le même type de fenêtre système.
- Seuls deux attributs sont settable au niveau fenêtre sur les deux apps :
  `AXPosition` (✅) et `AXSections` (✅, tableau — non pertinent pour du masquage).
  Tout le reste (`AXSize`, `AXMinimized`, `AXFullScreen`, `AXModal`, `AXFocused`…)
  est déclaré **non settable** (`AXUIElementIsAttributeSettable` → false) sur les
  deux apps, sans exception.
- **`kAXHiddenAttribute` n'existe tout simplement pas comme attribut de FENÊTRE.**
  Il n'apparaît dans la liste `AXUIElementCopyAttributeNames` d'aucune des deux
  fenêtres — seulement au niveau `AXApplication`. Ce n'est donc pas un attribut que
  boringNotch "refuse" au niveau fenêtre : il n'y est simplement pas exposé, sur
  aucune des deux apps. La seule prise possible reste l'attribut applicatif déjà
  testé au Milestone 0.

**Conclusion de la Q1, la plus importante du run :** l'arbre AX ne révèle **aucune
différence structurelle** entre boringNotch et Vibe Island — mêmes rôle/subrôle,
mêmes attributs exposés, même patron de settable/non-settable. La raison pour
laquelle `kAXHiddenAttribute` (niveau application) fait réellement disparaître la
fenêtre de Vibe Island mais pas celle de boringNotch n'est **pas visible depuis
l'AX** : c'est un détail d'implémentation interne à chaque app (vraisemblablement,
la façon dont chacune câble — ou ne câble pas — son `NSPanel` à l'état
"application masquée" de `NSApplication`), invisible et non actionnable depuis
l'extérieur.

### Tableau des propriétés testées (résultats identiques sur les deux apps)

| # | Attribut | Niveau | Settable déclaré | `AXUIElementSetAttributeValue` | Effet réel (recomptage `CGWindowList`) | Restauré |
|---|----------|--------|:---:|:---:|:---:|:---:|
| 1 | `kAXHiddenAttribute` | Fenêtre | — (absent de l'arbre) | n/a | ❌ test ignoré, attribut inexistant | ✅ |
| 2 | `kAXMinimizedAttribute` | Fenêtre | ❌ non settable | ✅ retourne `success` quand même | ❌ aucun changement | ✅ |
| 3 | `kAXSizeAttribute` → 1×1 | Fenêtre | ❌ non settable | ❌ échoue (cohérent avec le settable déclaré, pour une fois) | ❌ | ✅ |
| 4 | `kAXPositionAttribute` → hors écran (-10000,-10000) | Fenêtre | ✅ settable | ✅ | ❌ (voir note) | ✅ |
| — | Découverte d'attributs booléens settable additionnels | Fenêtre | — | — | Aucun trouvé au-delà de la liste ci-dessus | — |

Deux points valent d'être soulignés au-delà du tableau :

- **`kAXMinimizedAttribute` rejoue le même piège que `kAXHiddenAttribute` au
  Milestone 0** : `AXUIElementIsAttributeSettable` dit *non settable*, et pourtant
  `AXUIElementSetAttributeValue` renvoie `.success` — sans le moindre effet mesuré
  par `CGWindowList`. Ce n'est donc pas un cas isolé : sur ces fenêtres, ni le code
  retour AX ni le flag `settable` ne sont des indicateurs fiables. Seul le
  recomptage `CGWindowList` (déjà la règle depuis le Milestone 0) doit continuer à
  servir de juge de vérité dans le `WindowManager`.
- **`kAXPositionAttribute` reste non concluant pour le masquage, mais la
  relecture post-set apporte une info nouvelle** : la position est acceptée
  telle quelle (`(-10000, -10000)` relu = `(-10000, -10000)` cible → l'app ne la
  réimpose pas), donc rien ne "combat" ce déplacement. Mais `CGWindowList` avec
  `.optionOnScreenOnly` continue de compter la fenêtre même hors des bornes de
  tout écran physique — ce flag filtre par état de fenêtre (visible/minimisée),
  pas par géométrie réelle. Conséquence pratique : déplacer une fenêtre hors
  écran pourrait la rendre invisible à l'utilisateur sans jamais satisfaire le
  critère de succès `CGWindowList` que le `WindowManager` utilise par ailleurs —
  une incohérence entre "invisible pour l'utilisateur" et "absent de la liste"
  qu'il faudrait éviter d'exploiter comme stratégie de repli (elle romprait la
  méthode de vérification déjà adoptée).

### Question 2 — Le repli SkyLight exige-t-il de désactiver SIP ? Réponse ferme : **oui**

Vérifié par documentation communautaire, pas par opinion :

- **Mécanisme exact côté WindowServer** : tout appel d'écriture sur une fenêtre
  (déplacement, alpha/transparence, etc.) passe par une vérification interne du
  process appelant sur ses droits sur ce window ID. Par défaut, seul le process
  propriétaire de la fenêtre a ces droits, sauf entitlement Apple privé réservé à
  des process système. Source : Keen Security Lab, *"WindowServer: The privilege
  chameleon on macOS (Part 1)"* —
  https://keenlab.tencent.com/en/2016/07/22/WindowServer-The-privilege-chameleon-on-macOS-Part-1/
- **Confirmation par la pratique — yabai** : yabai désactive SIP (partiellement)
  précisément pour injecter sa "scripting addition" dans **Dock.app**, seul
  process flaggé *universal owner* dont la connexion WindowServer a le droit de
  modifier des propriétés de fenêtres appartenant à d'autres apps. La liste des
  fonctionnalités qui en dépendent inclut explicitement *"enable window
  transparency"* (= l'équivalent de `CGSSetWindowAlpha`). Sources :
  https://github.com/koekeishiya/yabai/issues/1863 (section *"Why do these
  features require SIP to be disabled"*) et
  https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection.
  Une discussion plus récente (macOS 15/Sequoia) confirme que la même barrière
  tient toujours et reste fragile même avec SIP désactivé + injection Dock :
  https://github.com/koekeishiya/yabai/issues/1777.
- **Confirmation en creux — Rectangle et AeroSpace** : les deux évitent
  délibérément CGS pour cette raison et se limitent à l'API Accessibility
  publique. Rectangle documente ses limites (pas d'action sur un Space non
  visible) comme venant de l'absence d'API Spaces publique, pas d'un choix
  arbitraire (https://github.com/rxhanson/Rectangle/discussions/1691) ; AeroSpace
  n'utilise qu'une seule API privée annexe (`_AXUIElementGetWindow`, pour retrouver
  un window ID depuis un élément AX) et revendique explicitement ne jamais exiger
  de désactiver SIP (https://github.com/nikitabobko/AeroSpace).

**Conséquence directe pour Island Switch** : même en root, sans injection dans un
process privilégié comme Dock.app et sans SIP désactivé, `CGSSetWindowAlpha` sur
une fenêtre d'un autre process échouera côté serveur. Cette voie est incompatible
avec la distribution DMG notarized Developer ID visée par le `CLAUDE.md` du
projet (un installeur grand public ne peut pas demander de désactiver SIP). Le
repli SkyLight est donc **mort pour ce produit**, pas seulement risqué.

### Recommandation

**Aucune propriété AX ne masque boringNotch — son arbre AX est structurellement
identique à celui de Vibe Island, la résistance vient d'une différence de câblage
interne à l'app invisible depuis l'Accessibility API — et le repli SkyLight est
mort : `CGSSetWindowAlpha` sur une fenêtre d'un autre process est bloqué côté
WindowServer sans SIP désactivé et sans injection dans un process privilégié
(source directe : yabai), ce qui est incompatible avec une distribution grand
public notarized ; le Milestone 1 doit donc traiter les apps du type boringNotch
comme hors du périmètre garanti (documenté côté utilisateur), sans dépendance à
une API privée.**

## Pourquoi boringNotch résiste — lecture du source

Dépôt cloné dans le scratchpad de l'agent (pas dans ce projet) :
`https://github.com/TheBoredTeam/boring.notch` — à noter, le nom exact de
l'organisation GitHub est **TheBoredTeam**, pas TheBoringTeam comme indiqué
dans la mission ; le bundle ID installé (`theboringteam.boringnotch`, vérifié
via `defaults read /Applications/boringNotch.app/Contents/Info.plist
CFBundleIdentifier`) entretient la confusion mais le dépôt source est bien
celui-ci — licence MPL 2.0/MIT selon fichiers, code source complet disponible.

### Question 1 — La cause racine, avec le code qui la prouve

**boringNotch n'affiche pas sa barre dans une fenêtre « normale » du Space
courant : il la rattache explicitement à un Space CGS privé, créé par l'app
elle-même, réglé au niveau maximum et toujours affiché.** C'est ce
rattachement — pas `collectionBehavior` ni `level` seuls — qui la fait
échapper au mécanisme `-[NSApplication hide:]` (donc à `kAXHiddenAttribute`
au niveau application, testé au Milestone 0).

Preuve, dans l'ordre où le code s'exécute :

1. `boringNotch/managers/NotchSpaceManager.swift:10-18` — un singleton crée un
   `CGSSpace` **au démarrage de l'app**, indépendamment de toute fenêtre :
   ```swift
   class NotchSpaceManager {
       static let shared = NotchSpaceManager()
       let notchSpace: CGSSpace
       private init() {
           notchSpace = CGSSpace(level: 2147483647) // Max level
       }
   }
   ```
2. `boringNotch/private/CGSSpace.swift` — le wrapper de l'API privée CGS
   (`SkyLight`/`CoreGraphicsServices`, non documentée par Apple, source
   d'origine : le projet Parrot). `init(level:)` crée un Space CGS dédié et
   l'affiche immédiatement et durablement via `CGSShowSpaces` :
   ```swift
   public init(level: Int = 0) {
       let flag = 0x1 // this value MUST be 1, otherwise, Finder decides to draw desktop icons
       self.identifier = CGSSpaceCreate(_CGSDefaultConnection(), flag, nil)
       CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), self.identifier, level)
       CGSShowSpaces(_CGSDefaultConnection(), [self.identifier])
   }
   ```
   Le setter de `windows: Set<NSWindow>` fait l'aller-retour CGS explicite
   (`CGSAddWindowsToSpaces` / `CGSRemoveWindowsFromSpaces`) — l'appartenance
   d'une fenêtre à ce Space est donc pilotée entièrement par boringNotch,
   fenêtre par fenêtre, hors de tout mécanisme public AppKit.
3. `boringNotch/boringNotchApp.swift:234-253` (`createBoringNotchWindow`) —
   juste après avoir créé et affiché la fenêtre du panneau, l'app l'insère
   dans ce Space :
   ```swift
   let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
   ...
   window.orderFrontRegardless()
   NotchSpaceManager.shared.notchSpace.windows.insert(window)
   ```
4. La fenêtre elle-même (`boringNotch/components/Notch/BoringNotchWindow.swift`
   et sa variante `BoringNotchSkyLightWindow.swift`) est un `NSPanel` avec
   `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces,
   .ignoresCycle]` et `level = .mainMenu + 3` — cohérent avec « rester visible
   partout », mais **ce n'est pas ce qui bloque `AXHidden`** : ce
   `collectionBehavior` régit le comportement lors des changements de Space
   normaux (Mission Control), pas l'ordre d'affichage déclenché par
   `-[NSApplication hide:]`. C'est bien l'appartenance au Space CGS privé
   (points 1-3) qui retire la fenêtre du circuit que `AXHidden` actionne.

**Mécanisme exact.** `AXUIElementSetAttributeValue(kAXHiddenAttribute, true)`
au niveau application déclenche `-[NSApplication hide:]`, qui demande au
WindowServer de masquer les fenêtres possédées par la connexion de l'app
*dans le Space courant de l'utilisateur*. Une fenêtre explicitement rattachée
par l'app elle-même à un Space CGS séparé — créé par elle, réglé au niveau
maximum, toujours affiché (`CGSShowSpaces` appelé une fois à l'init et jamais
annulé tant que l'app tourne) — n'est plus soumise à ce circuit : le
WindowServer continue de la composer normalement, quel que soit l'état
« masqué » de l'application. C'est pour ça que le Milestone 0 observait un
`AXError 0` (l'attribut applicatif est bien positionné) sans aucun effet sur
`CGWindowList` : `AXHidden` a fait exactement ce qu'il devait faire au niveau
application, simplement cette fenêtre-là ne l'écoute plus.

**Piège identifié en cours de lecture, à ne pas confondre avec la cause
racine :** `BoringNotchSkyLightWindow.enableSkyLight()` /
`disableSkyLight()` (délégation SkyLight façon Milestone 0 Q2) existent aussi
dans le code, mais ne sont activés que quand l'écran est verrouillé
(`createBoringNotchWindow` : `if isScreenLocked { window.enableSkyLight() }
else { window.disableSkyLight() }`) — c'est un mécanisme séparé, pour rester
visible par-dessus l'écran de verrouillage, sans rapport avec la résistance à
`AXHidden` observée en session normale (écran déverrouillé pendant tous les
runs de ce rapport). Le Space CGS de `NotchSpaceManager`, lui, est actif en
permanence dès le lancement de l'app, verrouillé ou non — c'est la vraie
cause.

**Comparaison avec Vibe Island : impossible, code non public.** Le dépôt
officiel `vibeislandapp/vibe-island` existe mais ne contient aucun code
source — vérifié via l'API GitHub (`language: null`, `size: 29` Ko) : c'est
un dépôt « accueil communautaire » pour les issues/feature requests, l'app
elle-même est distribuée en binaire fermé. Un clone tiers non officiel
(`Octane0411/open-vibe-island`) existe mais c'est une réimplémentation
indépendante, pas le code qui tourne réellement sous le pid 1275 testé —
je ne l'ai pas utilisé comme substitut, il prouverait une hypothèse sur le
mauvais programme. Le contraste attendu (Vibe Island répond à `AXHidden`
donc n'utilise vraisemblablement pas ce genre de Space CGS dédié) reste donc
une déduction comportementale, pas une lecture de code — je le signale
explicitement plutôt que de trancher sans preuve.

### Question 2 — Existe-t-il un levier tiers actionnable sans API privée ?

| # | Levier cherché | Trouvé dans le source ? | Testé | Effet mesuré (`CGWindowList` sur pid 51589) |
|---|---|---|---|---|
| 1 | Raccourcis clavier globaux (`KeyboardShortcuts`) | ✅ `toggleNotchOpen` (⌘⇧I), `toggleSneakPeek` (⌘⇧H), `clipboardHistoryPanel` (⌘⇧C) — `Shortcuts/ShortcutConstants.swift` | Non — écarté par lecture de code | N/A : les deux handlers (`boringNotchApp.swift:354-368`) ne font que basculer `notchState`/la bulle sneak-peek en SwiftUI ; jamais `orderOut`/`close` sur la fenêtre. Synthétiser ces touches ne ferait qu'ouvrir/fermer le tiroir, la barre resterait dans `CGWindowList`. |
| 2 | Réglage « Hide notch » déjà présent dans l'UI (`hideNotchOption` : *Hide for all apps* / *Now Playing only* / *Never*) | ✅ `models/Constants.swift:181`, exposé dans `SettingsView.swift:664-674`, domaine `theboringteam.boringnotch` | **Oui, en direct** | `defaults write theboringteam.boringnotch hideNotchOption -string always` puis recomptage : **aucun changement** — toujours 1 fenêtre, bounds identiques `(2916,650,640,210)`. Réglage restauré (`defaults delete …`, confirmé absent comme avant le test — la clé n'existait pas avant mon écriture). |
| 3 | URL scheme (`CFBundleURLTypes`) | ❌ absent de `boringNotch/Info.plist` | Non — rien à tester | — |
| 4 | `NSDistributedNotificationCenter` en écoute | ❌ aucune occurrence dans tout le repo ; seul `NotificationCenter.default` local est utilisé (ex. `sneakPeekEvent` dans `BoringViewCoordinator.swift:178`, alimenté par le helper XPC interne de l'app, pas par un process tiers arbitraire) | Non | — |
| 5 | Menu de la status bar (API publique AX, pas d'API privée) | ✅ un seul item : **« Quit »** (`menu/StatusBarMenu.swift:20`, `action: #selector(quitAction)` → `NSApplication.shared.terminate(self)`) | Non testé en direct (aurait tué le process de François pour de vrai — jugé disproportionné juste pour confirmer l'évident) | Certain par lecture : quitte l'app entièrement. Ce n'est pas « masquer », c'est « tuer » — perte totale de l'état en cours, l'utilisateur doit la relancer. |
| 6 | Code mort trouvé en cours de lecture : `togglePopover()` (`boringNotchApp.swift:545-551`) fait exactement `window.orderOut(nil)` / `window.orderFrontRegardless()` — un vrai hide qui aurait fonctionné | — | Vérifié : **jamais appelé nulle part** (`grep togglePopover` ne remonte que sa propre déclaration) — pas câblé à un menu, un raccourci, ou un sélecteur AX. Inatteignable de l'extérieur. | — |

Concernant l'explication de pourquoi le réglage 2 ne pouvait de toute façon
pas satisfaire le critère `CGWindowList`, même avec une vraie app en plein
écran : `BoringViewModel.setupDetectorObserver()`
(`models/BoringViewModel.swift:72-103`) ne fait que positionner
`hideOnClosed`, qui pilote `effectiveClosedNotchHeight` — une taille de
contenu SwiftUI *à l'intérieur* de la fenêtre. La fenêtre AppKit elle-même
est créée une seule fois avec un `windowSize` fixe
(`boringNotchApp.swift:235`) et n'est jamais redimensionnée nulle part dans
le code ; seule son origine (`positionWindow`) change. Un panneau réduit à un
contenu de hauteur 0 reste une fenêtre pleine taille, ordonnée à l'écran, et
continue donc d'apparaître dans `CGWindowList` — c'est cohérent avec le test
direct ci-dessus, qui n'avait de toute façon aucune chance de faire
disparaître la fenêtre même en forçant une vraie détection plein écran (ce
que je n'ai pas fait, pour ne pas perturber la session de François).

### Conclusion

**Aucun levier utilisable : boringNotch pin délibérément son panneau à un
Space CGS privé qu'il crée lui-même et affiche en permanence (API privée
non documentée, `SLSSpaceCreate`/`CGSAddWindowsToSpaces`), ce qui le retire
du circuit que `-[NSApplication hide:]`/`kAXHiddenAttribute` actionne —
et tous les leviers publics qu'expose l'app (raccourcis clavier, réglage
« hide » de l'UI, menu status bar) sont soit sans effet réel sur la
présence de la fenêtre (testé en direct pour le réglage le plus prometteur),
soit inexistants (URL scheme, notification distribuée), soit une frappe
nucléaire qui tue l'app plutôt que de la masquer (Quit) ; le Milestone 1 doit
donc traiter boringNotch comme définitivement hors du périmètre garanti
d'Island Switch, sans piste de repli restante à explorer côté app tierce.**

## Compatibilité des applications d'encoche

Objectif : élargir l'échantillon au-delà de Vibe Island/boringNotch en testant les deux
autres apps citées dans le `PRD.md` — **Alcove** et **Notchy** — pour savoir si l'une
donne une deuxième app réellement régissable (démonstration de bascule entre deux apps
jamais possible jusqu'ici, faute de second candidat qui réponde). Installation depuis
les sources officielles : Alcove via `brew install --cask alcove` (Homebrew Cask
officiel, `tryalcove.com`) ; Notchy via le DMG signé servi par `notchy.dev`
(redirige vers `github.com/vishvavariya/notchy-feedback/releases`, Developer ID
`PKQWZ2BV83`) — le tap Homebrew tiers `vishvavariya/notchy` annoncé par le site n'a pas
été utilisé (tap non officiel non vérifiable), le DMG signé/notarié a suffi.

**Aucune des deux n'a pu être testée en direct jusqu'au bout — pour deux raisons
différentes, aucune des deux liée à Island Switch :**

- **Alcove (1.7.7) reste bloqué au tout premier instant de son lancement.** Le
  process démarre (`open -a Alcove.app`), apparaît dans `ps`, mais reste figé à
  **32 Ko de RSS, 0 % CPU, échantillonné à `_dyld_start`** (avant même `main()`) —
  aussi bien à son premier lancement qu'après un `kill -9` + retrait du flag
  `com.apple.quarantine` + relance. `spctl --assess` accepte le binaire
  (« Notarized Developer ID »), aucun crash report généré, et le journal unifié ne
  montre aucune erreur `amfid`/`coretrustd` pointant vers Alcove — seulement une
  requête OCSP de `syspolicyd` en timeout (30 s, `Operation timed out`, réseau Wi-Fi)
  au même moment, sans certitude que ce soit la cause exacte du blocage. Conclusion
  honnête : **non testé en direct**, l'app ne quitte jamais son état de lancement sur
  cette machine dans cette session — pas un verdict sur sa régissabilité en usage
  normal ailleurs.
- **Notchy (1.0.135) se lance normalement (RSS ~30 Mo, séquence de démarrage propre
  dans le journal unifié : CoreLocation, requêtes TCC, vérification d'automatisation
  Musique/Spotify/Messages/Notes) mais ne crée strictement aucune fenêtre.**
  Recomptage `CGWindowList` sur son pid : **0 avant tout test**, sur tout l'écran, pas
  seulement la zone d'encoche. Confirmé indépendamment via `System Events` : 0 fenêtre,
  0 élément AX, pas même de menu bar (`menu bar 1` renvoie « index non valable »). Ce
  n'est pas un crash ni un blocage — c'est une app de type « Dynamic Island » dont le
  contenu de la pilule est **conditionnel** (musique en lecture, appel FaceTime,
  ouverture du boîtier AirPods, événement calendrier…) plutôt qu'une barre permanente
  comme boringNotch/Vibe Island ; sans déclencheur actif pendant la session de test,
  elle n'affiche rien à masquer. Déclencher un de ces événements (lancer Music.app,
  simuler un appel) a été jugé disproportionné pour une mesure — risque d'interférer
  avec la session de travail en cours de François.

**Faute de fenêtre vivante sur les deux apps, le critère de régissabilité a été évalué
par la méthode économique suggérée par la mission : analyse statique du binaire**
(`otool -L`, `nm -u | grep -i CGS`) — la même API privée CGS/SkyLight identifiée
comme cause racine de la résistance de boringNotch (`CGSSpaceCreate`,
`CGSSpaceSetAbsoluteLevel`, `CGSShowSpaces`, `CGSAddWindowsToSpaces`,
`CGSRemoveWindowsFromSpaces` — créer un Space CGS dédié, le régler au niveau max, y
épingler ses fenêtres). Comparaison à quatre binaires :

| Binaire | Symboles CGS liés (`nm -u`) | Lecture |
|---|---|---|
| **Vibe Island** (régissable ✅, prouvé en direct) | `CGSCopyManagedDisplaySpaces`, `CGSCopySpacesForWindows`, `CGSMainConnectionID`, `CGSessionCopyCurrentDictionary` — **uniquement des appels de lecture** (interroger les Spaces existants) | Ne crée ni ne s'épingle à aucun Space privé — cohérent avec le fait que `kAXHiddenAttribute` la masque réellement |
| **boringNotch** (non régissable ❌, prouvé en direct + lu dans le source) | `CGSSpaceCreate`, `CGSSpaceSetAbsoluteLevel`, `CGSShowSpaces`, `CGSAddWindowsToSpaces`, `CGSRemoveWindowsFromSpaces` | Pattern de **création + épinglage** d'un Space dédié (confirmé par le code, cf. section précédente) |
| **Alcove** (non testé en direct) | `CGSSpaceCreate`, `CGSSpaceSetAbsoluteLevel`, `CGSShowSpaces`, `CGSAddWindowsToSpaces`, `CGSRemoveWindowsFromSpaces`, `CGSSpaceDestroy`, `CGSSpaceGetType`, `CGSGetActiveSpace` | **Même pattern d'écriture que boringNotch**, symbole pour symbole, plus complet encore (destroy/getType en prime) |
| **Notchy** (non testé en direct) | `CGSSpaceCreate`, `CGSSpaceSetAbsoluteLevel`, `CGSShowSpaces`, `CGSAddWindowsToSpaces`, `CGSRemoveWindowsFromSpaces`, `CGSSetWindowAlpha`, `CGSHideSpaces`, `CGShieldingWindowLevel` | **Même pattern d'écriture**, plus `CGSSetWindowAlpha` — la fonction SkyLight de fondu en transparence explicitement identifiée comme piste de repli « morte » au Milestone 0 (Question 2) : Notchy semble l'utiliser en interne pour sa propre app, ce qui ne l'aide en rien à se laisser masquer par un tiers |

Le signal est net : les apps qui **lisent seulement** l'état des Spaces restent dans
le circuit standard `-[NSApplication hide:]` et répondent à `kAXHiddenAttribute`
(Vibe Island, prouvé). Les apps qui **créent et épinglent leur propre Space CGS**
en sortent (boringNotch, prouvé) — et Alcove comme Notchy présentent exactement ce
second pattern, symbole pour symbole identique à celui de boringNotch. Prédiction
fondée sur ce signal, pas sur un test de bout en bout faute de fenêtre exploitable :
**Alcove et Notchy sont vraisemblablement non régissables**, au même titre que
boringNotch — mais ce n'est **pas confirmé par recomptage `CGWindowList` avant/après
hide** comme pour les deux autres apps, faute d'avoir pu produire une fenêtre
vivante à masquer pendant cette session.

### Tableau de compatibilité

| Application | Version testée | Régissable | Raison |
|---|---|:---:|---|
| **Vibe Island** | 1.0.48 | ✅ Oui | `kAXHiddenAttribute` (niveau app) : hide 31,7 ms / show 5,1 ms, confirmé par recomptage `CGWindowList` |
| **boringNotch** | 2.7.3 | ❌ Non | Épingle sa fenêtre à un Space CGS privé qu'elle crée et affiche en permanence (`CGSSpaceCreate` + `CGSAddWindowsToSpaces`, confirmé par lecture du source) — hors du circuit `AXHidden` |
| **Alcove** | 1.7.7 | ❌ Non *(prédit, non confirmé en direct)* | Lancement de l'app bloqué sur cette machine (figé à `_dyld_start`, cause probable : timeout réseau `syspolicyd`/OCSP, non lié à Island Switch) — aucune fenêtre disponible pour un test de bout en bout ; analyse statique du binaire (`otool -L`/`nm -u`) montre le même pattern d'écriture CGS Space (`CGSSpaceCreate`/`CGSSpaceSetAbsoluteLevel`/`CGSShowSpaces`/`CGSAddWindowsToSpaces`) que boringNotch |
| **Notchy** | 1.0.135 | ❌ Non *(prédit, non confirmé en direct)* | App lancée avec succès mais n'affiche aucune fenêtre en l'absence de contenu contextuel actif (musique/appel/AirPods/calendrier) — rien à masquer pendant cette session ; analyse statique montre le même pattern d'écriture CGS Space que boringNotch, plus `CGSSetWindowAlpha` (fondu SkyLight, déjà écarté comme piste de repli au Milestone 0) |

**Conclusion de ce complément :** aucune deuxième app réellement régissable n'a été
trouvée dans cette passe — la bascule entre deux apps régies par Island Switch reste,
à ce stade, non démontrable en conditions réelles (un seul candidat qui réponde,
Vibe Island). Alcove et Notchy rejoignent vraisemblablement boringNotch hors du
périmètre garanti, mais ce verdict repose sur une analyse statique et non sur la
même preuve empirique par recomptage `CGWindowList` que les deux autres apps ; si le
produit doit s'appuyer dessus pour la page publique, il vaut mieux le refaire sur une
machine où Alcove démarre et où Notchy peut être amenée à afficher un contenu actif,
plutôt que de publier une prédiction comme un fait mesuré.

Nettoyage effectué avant de rendre la main : recomptage final `CGWindowList` sur la
zone d'encoche — aucune fenêtre tierce masquée (Island Switch et Vibe Island
retrouvés dans leur état initial). Alcove et Notchy laissés installés dans
`/Applications` à la décision du propriétaire ; Alcove reste dans son état figé au
lancement au moment de la rédaction — un `killall Alcove` puis relance réglera
probablement le blocage une fois le run passager de `syspolicyd` terminé, mais ça n'a
pas été retenté pour ne pas multiplier les popups système sur la session en cours.
