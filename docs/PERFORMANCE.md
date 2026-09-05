# Rapport d'Audit de Performance et Fluidité — Bouncer

> Date : 5 septembre 2026  
> Contexte : Analyse chiffrée de la fluidité de Bouncer (lecture seule, zéro modification de code de production).  
> Machine de référence : MacBook Pro (Apple M4, 10 cœurs : 4 performance, 6 efficience, 16 Go RAM), macOS 14+ Sonoma/Sequoia.  
> Configuration d'affichage : Écran externe LG IPS QHD (2560×1440 @ 60 Hz, écran principal) + Écran interne Liquid Retina XDR (1352×878, écran secondaire portant l'encoche physique de 166×29 pt).

---

## 1. Synthèse exécutive

La question posée par François : *« Comment on peut rendre l'app hyper fluide dans son fonctionnement ? »*

L'analyse du code et les mesures sur machine réelle révèlent un constat net :
1. **La cause n°1 de la sensation d'accroche n'est pas là où on l'attendait.** Ce n'est ni le calcul du survol souris ni le détecteur de swipe. C'est un **`usleep(300_000)` synchrone sur le `MainActor`** dans `ControleurAppsSysteme.masquer()`. Chaque bascule entre deux apps régissables fige le thread principal pendant **600 ms** (300 ms pour afficher la cible + 300 ms pour masquer l'actuelle). La propagation réelle de WindowServer ne prend pourtant que **1,5 à 32 ms**.
2. **Le suspect n°1 de départ (`.mouseMoved`) a déjà été traité au commit `0797023`.** Avant ce commit, `updateHover()` coûtait **231 µs** par événement et déclenchait SwiftUI. Depuis la mise en cache de `zoneSensible`, le calcul ne prend plus que **0,06 µs (64 ns)**. Le seul coût résiduel est le réveil de la runloop par WindowServer (120 à 1000 wakeups/s sur tout l'écran).
3. **Le timer de 2 s (`scanNotchApps`) consomme 2,68 ms à chaque tour**, même machine inactive, et force un redessin SwiftUI via `@Published lastNotchZoneDescription` qui émet systématiquement. Il peut être remplacé par des notifications système `NSWorkspace`.
4. **Le monitor `.scrollWheel` écoute tous les défilements du Mac** (86 événements par geste) alors que Bouncer n'en a besoin qu'au survol de l'encoche. Il suffit de ne l'attacher que lorsque le curseur est en approche (`opacite > 0`).

---

## 2. Tableau comparatif des mesures

| Composant / Action | Coût mesuré (Avant / Actuel) | Coût cible (Après correctif proposé) | Facteur de gain |
| :--- | :--- | :--- | :--- |
| **Bascule d'apps (freeze UI)** | **600,0 ms** (freeze thread principal) | **~35,0 ms** (asynchrone, 0 ms freeze) | **x17 plus rapide** (0 freeze) |
| **Propagation WindowServer masquage** | 300,0 ms imposés par `usleep` | **1,52 ms à 31,7 ms** (mesuré réel) | **x10 à x200** |
| **Calcul unitaire `updateHover` (souris loin)** | 231,19 µs *(avant 0797023)* → **0,06 µs (64 ns)** | 0 µs (hors zone haute) | Négligeable en CPU |
| **Réveils runloop souris globale** | ~432 000 wakeups / heure active | Confiné à la zone supérieure | Économie de batterie |
| **Timer 2 s : `scanNotchApps()`** | **2,68 ms** toutes les 2 s (116 s CPU / 24h) | Événementiel (`NSWorkspace`), 0 en veille | **-98% CPU de fond** |
| **Timer 2 s : `CGWindowListCopyWindowInfo`** | **594 µs** (jusqu'à 43,9 ms à froid) | Uniquement sur événement / ouverture menu | Zéro appel périodique |
| **Invalidation SwiftUI par timer** | Émission Combine **toutes les 2 s** | 0 émission si l'état ne change pas | Zéro redessin parasite |
| **Monitor `.scrollWheel` global** | 100% des scrolls du Mac interceptés | 0 scroll intercepté hors zone encoche | Zéro pollution d'inbox |

---

## 3. Analyse détaillée des 5 points audités

### Point 1 — Le monitor global `.mouseMoved` (`NotchOverlay.swift`)

- **Hypothèse initiale :** Chaque mouvement de souris sur tout l'écran appelle `overlayZone()` → `WindowManager.notchZone()` → `zoneEncoche()`, recalculant les insets d'écran et modifiant un `@Published`.
- **Vérification dans le code :**
  - Cette hypothèse décrivait fidèlement le code **antérieur au commit `0797023`**.
  - Avant `0797023`, chaque mouvement déclenchait `zoneEncoche()` (227 µs) et réassignait `lastNotchZoneDescription`, envoyant un événement Combine vers SwiftUI. À 200 Hz de déplacement souris, cela mobilisait **46,2 ms de CPU par seconde (~4,6% d'un cœur)**.
  - Le commit `0797023` a résolu ce point : `rebuild()` calcule `zoneSensible` une seule fois, et `updateHover()` se contente d'évaluer la distance euclidienne avec `opaciteFleches()`.
- **Mesures actuelles :**
  - Curseur loin de l'encoche (sortie rapide) : **0,06 µs (64 nanosecondes)**.
  - Curseur en approche (calcul de distance `hypot`) : **0,06 µs (58 nanosecondes)**.
- **Diagnostic :** Le calcul mathématique est désormais optimal. La seule friction restante est le coût système macOS : un monitor global oblige le WindowServer à poster un événement Mach dans la runloop de Bouncer pour chaque micro-mouvement de curseur. Sur une heure d'utilisation continue, cela représente ~432 000 réveils de thread.

---

### Point 2 — Le timer de rafraîchissement 2 s (`WindowManager.swift`)

- **Hypothèse initiale :** Le timer de 2 s déclenche `CGWindowListCopyWindowInfo` en permanence, y compris quand rien ne bouge et que l'utilisateur ne regarde pas l'écran.
- **Mesures réelles :**
  - Appel `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` : **594,15 µs** (en régime établi sur 35 fenêtres) et **43,9 ms** au premier appel à froid.
  - Scan complet `scanNotchApps()` : **2,68 ms** par exécution.
    - Résolution `NSRunningApplication` pour 15 PIDs : **490 µs**.
    - Filtrage et calculs géométriques : ~1,6 ms.
  - En 24 heures d'inactivité, ce timer exécute 43 200 scans complets, consommant **116 secondes de temps CPU** sur une machine au repos.
- **Effet de bord SwiftUI découvert :**
  - Dans `WindowManager.notchZone()`, la ligne suivante est exécutée toutes les 2 secondes :
    ```swift
    lastNotchZoneDescription = "\(ecran) — \(rect)"
    ```
  - Même si la chaîne est rigoureusement identique, le setter d'une propriété `@Published` déclenche inconditionnellement `objectWillChange.send()` (prouvé par notre benchmark Combine).
  - Résultat : toutes les 2 secondes, SwiftUI reçoit l'ordre de réévaluer le `MenuBarExtra` et le `MenuBarContentView`.
- **Faisabilité du remplacement par notifications :**
  - `NSWorkspace.didLaunchApplicationNotification` : prévient immédiatement quand une app démarre.
  - `NSWorkspace.didTerminateApplicationNotification` : prévient immédiatement quand une app s'arrête.
  - `NSWorkspace.activeSpaceDidChangeNotification` : prévient lors des bascules d'espaces.
  - `NSApplication.didChangeScreenParametersNotification` : prévient lors des branchements d'écrans (déjà écouté par l'overlay).
  - Un scan périodique n'est utile que pour une app qui créerait/détruirait une fenêtre sans changer de cycle de vie (cas de boringNotch déployé). Même dans ce cas, un rafraîchissement à la demande (au clic sur le menu ou à l'approche du curseur) suffit amplement.

---

### Point 3 — Le monitor global `.scrollWheel` (`NotchOverlay.swift`)

- **Hypothèse initiale :** Le monitor global reçoit tous les scrolls de la machine, y compris les rafales d'inertie.
- **Mesures réelles :**
  - Coût unitaire d'un événement hors zone : **0,03 µs (31 nanosecondes)**.
  - Coût de rejet de l'inertie (`guard !e.inertie`) : **0,02 µs (15 nanosecondes)**.
- **Diagnostic structurel :**
  - Dans `NotchOverlayController.buildPanel()`, `scrollMonitor` est créé et n'est jamais libéré.
  - Quand l'utilisateur navigue sur le web ou lit un document, chaque geste de scroll génère entre 80 et 100 événements. Bouncer reçoit et traite ces événements sur son thread principal alors que le curseur est à des centaines de pixels de l'encoche.
  - Puisque `updateHover()` connaît en temps réel l'approche du curseur (`opacite > 0`), écouter le scroll quand `opacite == 0` est inutile.

---

### Point 4 — Redessins SwiftUI et écritures `@Published`

- **Diagnostic :**
  1. `lastNotchZoneDescription` ne sert que pour le mode CLI `--self-test` (`main.swift`). Il n'apparaît dans aucune vue de l'interface utilisateur. Pourtant, il est marqué `@Published` et réassigné toutes les 2 secondes.
  2. `MenuBarContentView` recalcule `windowManager.entreesMenu` à chaque invalidation. Celui-ci appelle `catalogue.installees()`, qui interroge LaunchServices via `NSWorkspace.shared.urlForApplication` sur le disque pour chaque app connue (coût mesuré : **50,07 µs** par passe).
  3. Bien que 50 µs soit faible dans l'absolu, ce travail disque est répété toutes les 2 secondes pour un menu fermé.

---

### Point 5 (Découverte majeure) — Le verrou de 600 ms dans la bascule d'apps

- **Le problème :**
  Dans `Sources/BouncerCore/ControleurApps.swift` (ligne 148) :
  ```swift
  public func masquer(_ masquee: Bool, pid: pid_t) -> Bool {
      let appElement = AXUIElementCreateApplication(pid)
      let countBefore = compteFenetres(pid: pid)
      AXUIElementSetAttributeValue(
          appElement, kAXHiddenAttribute as CFString, masquee ? kCFBooleanTrue : kCFBooleanFalse
      )
      usleep(300_000) // laisser le WindowServer propager, cf. Spike.swift
      let countAfter = compteFenetres(pid: pid)
      return masquee ? countAfter < countBefore : countAfter >= countBefore
  }
  ```
  `ControleurAppsSysteme` est annoté `@MainActor`.
  `usleep(300_000)` est un appel système C bloquant de 300 millisecondes sur le **thread principal**.
- **La chaîne d'exécution lors d'un swipe :**
  1. L'utilisateur swipe sur l'encoche.
  2. `Bascule.basculer()` appelle `allumer(cible)` :
     - Pour une cible régissable, il appelle `controleur.masquer(false, pid: cible)` → **Freeze main thread de 300 ms**.
  3. `Bascule.basculer()` appelle ensuite `eteindre(actuelle)` :
     - Pour l'app actuelle, il appelle `controleur.masquer(true, pid: actuelle)` → **Freeze main thread de 300 ms**.
  4. **Total : 600 ms de blocage complet de l'application.**
  Pendant ces 600 ms :
  - Le curseur ne reçoit plus de mise à jour d'opacité.
  - Les boutons chevrons restent figés.
  - L'interface ne rend aucune frame.
  - L'utilisateur ressent une latence majeure (« l'app accroche »).
- **Temps réel mesuré de WindowServer :**
  - Dans notre test de propagation en direct : **1,52 ms**.
  - Dans les résultats de `SPIKE_RESULTS.md` (sur Vibe Island réelle) :
    - `hide` confirmé en **31,7 ms**.
    - `show` confirmé en **5,1 ms**.
  - La valeur de 300 ms avait été posée arbitrairement dans le premier script de spike (`Spike.swift`) et a été recopiée telle quelle en production.

---

## 4. Recommandations concrètes et plan d'action

### Priorité 1 (P0) — Supprimer le freeze synchrone de 600 ms sur la bascule
**Fichier concerné :** `Sources/BouncerCore/ControleurApps.swift`

Remplacer le `usleep(300_000)` bloquant par une méthode asynchrone non-bloquante avec sondage court :
- Sonder toutes les 15 ms avec `Task.sleep(for: .milliseconds(15))`.
- Sortir dès que le recomptage de fenêtres confirme l'effet (habituellement entre 5 et 30 ms).
- Plafonner le timeout à 100 ms au lieu de 300 ms.
- **Résultat :** La bascule d'app devient quasi-instantanée (~35 ms au total au lieu de 600 ms) et le thread principal ne gèle jamais (0 ms de freeze).

### Priorité 2 (P1) — Activer le monitor `.scrollWheel` uniquement à l'approche
**Fichier concerné :** `Sources/Bouncer/NotchOverlay.swift`

- Dans `updateHover()` :
  - Quand `opacite > 0` et que `scrollMonitor == nil` : installer `scrollMonitor`.
  - Quand `opacite == 0` et que `scrollMonitor != nil` : retirer `scrollMonitor` et le remettre à `nil`.
- **Résultat :** Zéro interception d'événements de scroll sur 99,9% du temps d'utilisation de la machine. Zéro wake-up parasite pendant que l'utilisateur scroll sur Safari, Slack ou son éditeur.

### Priorité 3 (P2) — Passer le scan d'encoche en événementiel et raréfier le timer
**Fichiers concernés :** `Sources/BouncerCore/WindowManager.swift`, `Sources/Bouncer/MenuBarContentView.swift`

- S'abonner aux notifications `NSWorkspace` (`didLaunchApplicationNotification`, `didTerminateApplicationNotification`, `activeSpaceDidChangeNotification`).
- Déclencher `refresh()` à la réception d'une notification ou à l'ouverture du menu (`onAppear`).
- Porter l'intervalle du timer de secours de 2 s à **60 s** (ou le désactiver quand la machine dort).
- **Résultat :** Élimination de 2,68 ms de scan CPU toutes les 2 secondes (économie de 116 s de CPU par jour).

### Priorité 4 (P3) — Supprimer l'invalidation SwiftUI parasite
**Fichier concerné :** `Sources/BouncerCore/WindowManager.swift`

- Retirer l'attribut `@Published` de `lastNotchZoneDescription` (ou ne publier que si la valeur a réellement changé via une garde `guard lastNotchZoneDescription != nouvelleDescription else { return }`).
- Mettre en cache le résultat de `catalogue.installees()` dans `CatalogueApps` avec invalidation uniquement sur `apprendre()`.
- **Résultat :** Zéro évaluation superflue du graphe SwiftUI du menu hors interaction utilisateur.

---

## 5. Conclusion chiffrée

En appliquant ces 4 correctifs :
1. **La réactivité de bascule passe de 600 ms de blocage à ~35 ms totalement fluides (gain perçu x17).**
2. **La consommation CPU d'arrière-plan chute de plus de 95%** en supprimant le polling agressif toutes les 2 s.
3. **Les réveils de runloop inutiles chutent drastiquement**, tant sur le scroll que sur les redessins SwiftUI.

Ce rapport fournit la cartographie exacte, mesurée et vérifiée sur le matériel de référence pour permettre à François d'arbitrer les chantiers à engager.

---

## Addendum du 5 septembre 2026 — la zone écoutée était 37 fois plus petite que la cible visée

Le point 4 ci-dessus a réduit le monitor `.scrollWheel` à la stricte zone utile. Il n'a pas
touché à la définition de cette zone, et c'est là qu'était le défaut remonté en test réel
(« pas mal de bugs au swipe, ça ne le détecte pas tout le temps »).

**Relevé.** Boîtier caméra : 166 × 29 pt. Zone écoutée : 254 × 41 pt (boîtier + 2 × 44 de marge).
Fenêtre réellement posée sur l'encoche : 640 × 210 pt (boringNotch), 740 × 520 pt (Vibe Island).
La zone écoutée couvrait donc **2,7 % de la surface que l'utilisateur voit et vise**.

**Rejoué à travers le pipeline de production**, trois gestes identiques posés sur l'île :

| Position du geste | Avant | Après |
|---|---|---|
| Dans la bande de 254 pt | 1 bascule | 1 bascule |
| Sur l'île, 180 pt à droite de la bande | 0 bascule — 13 rejets `horsZone` | 1 bascule |
| Sur l'île, 80 pt sous la barre des menus | 0 bascule — **aucune trace**, monitor non attaché | 1 bascule |

Le troisième cas est le plus instructif : il ne produisait aucune ligne de journal, donc aucune
prise pour le débogage. C'est ce que corrige `TraceSwipe`, qui note désormais **par quel garde**
chaque événement est tombé (`horsZone`, `sousLeSeuil`, `nonArme`, `inertie`…), plus l'attache et
le détachement du monitor.

**Ce qui a été écarté par la mesure, et pas par le raisonnement.** L'hypothèse de départ était que
le monitor global `.mouseMoved` cesse d'être alimenté dès que notre propre panel passe sous le
curseur — ce qui aurait figé `majMoniteurScroll`. Mesuré sur les trois configurations (panel
retiré, panel à l'écran, panel avec `ignoresMouseEvents`) : **11 événements reçus sur 11 dans les
trois cas**. Le panel n'y était pour rien.

**Coût du correctif.** Aucun sur le chemin chaud : la zone reste calculée une fois par `rebuild()`,
et le cadre des fenêtres d'encoche est dédupliqué avant publication (`publierCadre`) pour ne pas
reconstruire l'overlay à chaque tour du timer de 2 s.

---

## Addendum du 5 septembre 2026 — 9 tours de sondage en 95 s au lieu de 48

Le point 2 recommandait de remplacer le sondage par des notifications `NSWorkspace`. Cette
recommandation était fausse et n'a pas été appliquée telle quelle : **`NSWorkspace` n'émet aucune
notification à la création d'une FENÊTRE**. `didLaunchApplication` dit qu'un process a démarré,
pas que sa fenêtre d'encoche est à l'écran — et c'est exactement l'écart que le scan mesure. Une
app d'encoche pose sa fenêtre APRÈS son lancement, ce qui est le cas normal et non le cas limite.
Supprimer le sondage aurait cassé la découverte.

Le sondage reste donc en place. C'est sa cadence qui s'adapte.

### La règle

Le timer garde la période réglée (2 s par défaut) tant que quelque chose bouge. Chaque tour qui
retrouve exactement l'état du précédent incrémente un compteur ; au-delà de trois tours immobiles,
la période double à chaque cran, plafond à 30 s. Les notifications `NSWorkspace`
(`didLaunchApplication`, `didTerminateApplication`, `activeSpaceDidChange`), le branchement d'un
écran et l'entrée du curseur dans la zone sensible servent de **réveil** : ils resondent tout de
suite et remettent la cadence au plus rapide. Ils ne remplacent pas le sondage : ils lui disent
quand il vaut la peine de tourner vite.

Deux garde-fous :

- **Jamais de ralentissement sans droits d'Accessibilité.** Le passage refusé → accordé se fait
  dans les Réglages Système et aucune notification ne nous le dit : ce timer est la seule chose
  qui fait avancer l'écran d'accueil sous les yeux de l'utilisateur.
- **Plafond à 30 s, pas plus.** Une app d'encoche qui détruit sa fenêtre sans quitter son process
  n'émet rien du tout ; seul le sondage la voit. Au-delà de 30 s le menu resterait faux trop
  longtemps.

### Mesures

Coût d'un tour de scan, rejoué sur la machine de référence avec la méthode du point 2
(`CGWindowListCopyWindowInfo` + résolution `NSRunningApplication` + filtrage géométrique,
médiane sur 200 appels) : **2,30 ms sur 32 fenêtres à l'écran** — le rapport initial relevait
2,68 ms sur 35 fenêtres, le coût suit le nombre de fenêtres. Ce coût **ne change pas** : c'est le
même scan. Ce qui change, c'est le nombre de tours.

| Régime | Tours / 24 h | CPU / 24 h à 2,30 ms le tour |
|---|---|---|
| Avant — timer à 2 s fixes | 43 200 | 99,4 s |
| Après — machine jamais touchée | 2 886 | 6,6 s (**−93 %**) |
| Après — journée réaliste, 650 réveils | 6 811 | 15,7 s (**−84 %**) |
| Après — pire cas, un réveil toutes les 5 s pendant 16 h | 35 524 | 81,7 s (−18 %) |

Le nombre de tours est obtenu en déroulant 24 h de planification sur l'échelle de PRODUCTION
(`WindowManager.periodeDeRepos`, la même fonction que celle qui pose le timer), pas sur une copie.

### Relevé sur le binaire

Le compteur de tours est journalisé par `TraceSwipe` (éteint par défaut, cf. son en-tête). Relevé
sur une exécution réelle de 95 s, un tour par ligne :

```
 2,46 s  immobiles=0  periode=2      12,54 s  immobiles=4  periode=4
 4,46 s  immobiles=1  periode=2      21,67 s  immobiles=5  periode=8
 6,46 s  immobiles=2  periode=2      37,68 s  immobiles=6  periode=16
 8,46 s  immobiles=3  periode=2      69,68 s  immobiles=7  periode=30
```

**9 tours en 95 s, là où le timer fixe en aurait fait 48.** Les instants ne tombent pas rond (12,54 au lieu de
12,46) : c'est la tolérance de 20 % posée sur le timer, qui laisse macOS grouper notre réveil
avec ceux des autres process au lieu de sortir le CPU du repos rien que pour nous.

Et le réveil, sur la même exécution : à 75 s, cadence à 30 s depuis longtemps, `open -a TextEdit`.
La ligne suivante tombe à **75,16 s avec `immobiles=0 periode=2`** — cadence pleine restaurée dans
la seconde. Idem à la fermeture de TextEdit, sur `didTerminateApplication`.

### La réactivité ne bouge pas

Une app d'encoche lancée après une heure de repos est découverte **aussi vite qu'avant** : son lancement poste `didLaunchApplication`, le
réveil remet la période à 2 s avant même que la fenêtre existe, et le sondage la voit au premier
tour suivant. Latence entre l'apparition de la fenêtre et sa découverte, selon le délai que met
l'app à poser sa fenêtre :

| Fenêtre posée à | Découverte | Timer fixe 2 s |
|---|---|---|
| +0,1 s du lancement | 1,90 s | ≤ 2,00 s |
| +0,5 s | 1,50 s | ≤ 2,00 s |
| +1,5 s | 0,50 s | ≤ 2,00 s |
| +3,0 s | 1,00 s | ≤ 2,00 s |

Le seul cas où l'utilisateur attend plus qu'avant est celui qu'aucune notification ne couvre : une
app déjà lancée qui fait apparaître ou disparaître sa fenêtre d'encoche toute seule. Il est borné
à 30 s dans le menu — et à zéro dès que le curseur approche de l'encoche, puisque l'approche est
elle-même un réveil. Un geste sur l'encoche part donc toujours d'un état frais.

### Ce qui reste en attente

Le point 4 (mise en cache de `catalogue.installees()`, 50 µs par évaluation du menu) n'est pas
traité ici. Il pesait 25 fois par minute par la faute du timer ; il en pèse maintenant deux, et
seulement menu ouvert. Le chantier a perdu son intérêt.
