# Ce que Bouncer voit, écrit et envoie

Bouncer demande l'autorisation **Accessibilité**, la plus intrusive que macOS
propose : elle permet de lire et de piloter l'interface de toutes les autres
applications. L'app est signée par un certificat inconnu, distribuée hors du
Mac App Store, et elle réclame ça au premier lancement. Se demander ce qu'elle
en fait est la bonne réaction.

Ce document répond avec des références au code, fichier et ligne, sur le commit
`2cb2e63` (5 septembre 2026). Les sections 1, 2, 7 et 8 ont été réécrites le
13 octobre 2026, au commit `a7f0eec`, quand l'envoi des rapports de plantage est
passé en option à cocher. Le code est public : chaque affirmation ci-dessous
se vérifie en ouvrant le fichier cité. Les zones d'ombre trouvées pendant l'audit
sont dans la dernière section, pas cachées ailleurs.

---

## 1. Bouncer ne parle à personne, sauf si vous cochez une case

**Une dépendance tierce, `sentry-cocoa`, coupée par défaut.**

`Package.swift` déclare une seule dépendance externe :
[sentry-cocoa](https://github.com/getsentry/sentry-cocoa) 9.28.0, le SDK de
rapports de plantage de Sentry. `Package.resolved` fige sa version et celle de
KSCrash 2.6.0, qu'il embarque pour attraper les plantages. Le reste de l'app se
compile à partir de frameworks Apple :

| Framework | Ce qu'il sert |
|---|---|
| Foundation, AppKit, SwiftUI, Combine | l'app elle-même |
| CoreGraphics | `CGWindowList`, la liste des fenêtres |
| ApplicationServices | l'API Accessibilité |
| ServiceManagement | la case « lancer au démarrage » |

### Tant que vous n'avez rien coché, rien ne part

Le SDK n'est démarré que par `PiloteRapportsPlantage`
(`Sources/BouncerCore/RapportsPlantage.swift`), et seulement quand le réglage
`bouncer.rapportsPlantage` passe à vrai. Ce réglage vaut faux tant que vous ne
l'avez pas changé (`Reglages.swift:370`). Sans `SentrySDK.start`, le SDK
n'ouvre aucune connexion et ne crée pas ses dossiers de cache. Le test
`RapportsPlantageTests.coupeParDefaut` vérifie qu'avec le réglage par défaut, le
démarrage n'est jamais appelé.

L'interrupteur est dans le menu de Bouncer, dans la barre des menus :
« Envoyer les rapports de plantage ». Son infobulle dit ce qui part. Le décocher
appelle `SentrySDK.close()` (`Sources/Bouncer/App.swift:37`) et le SDK s'arrête
tout de suite, sans relancer l'app.

### Ce qui part si vous l'activez

Rien pendant que l'app tourne normalement. Quand Bouncer plante, KSCrash écrit
un rapport sur le disque, et le SDK l'envoie au lancement suivant. Le rapport
contient :

- la pile d'appels de chaque thread au moment du plantage, et le type d'erreur
  (`EXC_BAD_ACCESS`, `EXC_BREAKPOINT`…) ;
- la version de Bouncer (`bouncer@1.2.3`) et l'environnement `production` ;
- la version de macOS, le modèle du Mac, le processeur et l'état de la mémoire ;
- un identifiant d'installation tiré au hasard par le SDK et stocké dans son
  cache. Il sert à compter combien de Mac sont touchés par un même plantage.

Les réglages sont dans `Sources/Bouncer/App.swift:61-73` :

- `sendDefaultPii = false` : le SDK ne joint ni votre adresse IP, ni votre nom
  d'utilisateur, ni rien qui vous identifie. Le serveur de Sentry voit
  l'adresse de la connexion, comme n'importe quel serveur que votre Mac
  contacte ;
- `enableAutoSessionTracking = false` : pas de signal envoyé à chaque
  lancement. Seul un plantage produit un envoi ;
- pas de tracing ni de profiling : aucune mesure de performance ne part.

Bouncer ne lit pas les titres de fenêtres, le contenu des autres apps ou vos
fichiers (sections 3 à 5). Un rapport de plantage ne peut donc pas les contenir.

### Où ça part

Chez Sentry (Functional Software, Inc.), sur leur région européenne. La DSN,
l'adresse d'envoi écrite en dur dans `App.swift:63`, pointe sur
`o4511827012419584.ingest.de.sentry.io`, donc les données sont stockées en
Allemagne.

### Ce que Bouncer écrit sur le disque quand l'option est active

Le SDK garde ses fichiers dans `~/Library/Caches` : `SentryCrash/Bouncer/` (les
rapports en attente d'envoi), `io.sentry/` (l'identifiant d'installation et la
file d'envoi) et `Bouncer/async.log`. Option coupée, ces dossiers ne sont pas
créés. Pour les effacer après avoir décoché :

```
rm -rf ~/Library/Caches/SentryCrash/Bouncer ~/Library/Caches/Bouncer
```

`io.sentry/` peut aussi servir à d'autres apps qui utilisent Sentry. Ses
sous-dossiers portent un hash de la DSN de chaque app ; n'y supprimez que celui
de Bouncer si vous savez le reconnaître.

### Le reste du code

Pas de `URLSession`, de `NWConnection`, de `WKWebView` ni de socket dans le code
de Bouncer. Deux URL y apparaissent : la DSN de Sentry ci-dessus, et
celle-ci :

```swift
// Sources/BouncerCore/WindowManager.swift:160
URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
```

C'est un schéma d'URL local qui ouvre le volet Accessibilité des Réglages
Système. Il ne sort pas de la machine.

Bouncer ne lance pas non plus de sous-processus : pas de `Process`, pas de
`posix_spawn`, pas d'`osascript`. Le seul lancement possible est celui d'une app
d'encoche que vous avez choisie, par `NSWorkspace.openApplication`
(`ControleurApps.swift:176`).

### Vérifier vous-même

Dans le code :

```
grep -rniE 'URLSession|CFNetwork|NWConnection|socket|WKWebView|http|SentrySDK' Sources/
```

Sur une app installée, option coupée, aucune connexion ne doit apparaître. Avec
Little Snitch, LuLu ou, sans rien installer :

```
nettop -p "$(pgrep -x Bouncer)" -L 1
```

Une exception au réseau vient du gestionnaire de paquets, pas de l'app : si vous
installez par Homebrew, le `postflight` du cask exécute `xattr -dr
com.apple.quarantine` sur `/Applications/Bouncer.app`
(`Casks/bouncer.rb:22-25`). Voir la section 6.

## 2. Ce que Bouncer écrit sur votre disque

**Huit clés dans un fichier de préférences. Rien d'autre, tant que les rapports
de plantage sont coupés.**

Le code de Bouncer n'ouvre jamais de fichier en écriture : pas de
`FileManager.createFile`, pas de `Data.write`, pas de journal, pas de dossier
dans `Application Support`. Le cache du SDK Sentry, quand vous l'activez, est
décrit en section 1. Tout passe par `UserDefaults`, donc par le seul fichier
`~/Library/Preferences/io.github.donpaco13.bouncer.plist`.

| Clé | Contenu | Écrite dans |
|---|---|---|
| `bouncer.accueilVu` | booléen : la fenêtre d'accueil a été refermée une fois | `FenetreAccueil.swift:50` |
| `bouncer.modeActivation` | `swipe`, `fleches` ou les deux | `Reglages.swift:104` |
| `bouncer.porteeApproche` | nombre : distance d'apparition des flèches, en points | `Reglages.swift:161` |
| `bouncer.margeLaterale` | nombre : largeur de bande de chaque côté du boîtier caméra | `Reglages.swift:161` |
| `bouncer.intervalleRafraichissement` | nombre : période de resondage (1, 2, 5, 10 ou 30 s) | `Reglages.swift:161` |
| `bouncer.rapportsPlantage` | booléen : l'envoi des rapports de plantage, faux par défaut | `Reglages.swift:323` |
| `bouncer.bundleIDsExclus` | liste de bundleIDs que vous avez décochés du cycle | `Reglages.swift:169` |
| `bouncer.bundleIDsApprises.v2` | liste de bundleIDs vus au moins une fois dans l'encoche | `CatalogueApps.swift:86` |

Une neuvième clé, `bouncer.bundleIDsApprises` (sans le `.v2`), est **effacée** au
démarrage (`CatalogueApps.swift:73`) : c'est un ancien catalogue construit sous
un filtre de détection trop large, jeté volontairement.

Les deux dernières clés sont les seules qui décrivent votre machine plutôt que
vos préférences. Elles contiennent des identifiants d'applications, du type
`com.example.videnotch`, jamais un titre de fenêtre, un nom de fichier ou un
contenu. Une app entre au catalogue quand Bouncer la voit occuper l'encoche, et
elle y reste : c'est ce qui permet de la relancer une fois quittée.

Bouncer écrit une autre chose, hors du plist : si vous cochez « lancer au
démarrage », `SMAppService.mainApp.register()` (`FenetreReglages.swift:127`)
crée un élément d'ouverture géré par macOS. C'est la même mécanique que la case
dans Réglages Système › Général › Ouverture et éléments autorisés, et vous
pouvez la décocher là-bas.

**Tout désinstaller** revient donc à supprimer l'app, décocher le lancement au
démarrage, et jeter le plist :

```
rm ~/Library/Preferences/io.github.donpaco13.bouncer.plist
```

## 3. Ce que Bouncer fait de l'autorisation Accessibilité

**Un seul appel qui agit, sur un seul attribut : `kAXHiddenAttribute`.**

L'API Accessibilité permet de lire l'arborescence d'interface d'une app : ses
champs de texte, leur contenu, les titres de fenêtres, les boutons. Bouncer n'en
lit rien. Voici la totalité des appels AX du projet :

| Appel | Fichier:ligne | Ce qu'il fait |
|---|---|---|
| `AXIsProcessTrusted()` | `WindowManager.swift:124`, `:169` | demande à macOS si l'autorisation est accordée. Ne touche à aucune app. |
| `AXIsProcessTrustedWithOptions(prompt)` | `WindowManager.swift:127` | affiche la popup de demande, une seule fois, au démarrage à froid |
| `AXUIElementCreateApplication(pid)` | `ControleurApps.swift:205` | obtient une poignée sur une app par son pid |
| `AXUIElementSetAttributeValue(…, kAXHiddenAttribute, …)` | `ControleurApps.swift:207-209` | met l'app en « masquée » ou la réaffiche |

Il n'y a **aucun** `AXUIElementCopyAttributeValue` dans le projet : Bouncer
n'utilise pas la seule fonction qui lirait le contenu d'une autre app. Elle
n'observe pas non plus les notifications AX
(`AXObserverCreate`), qui permettraient de suivre en direct ce que vous faites
dans une app.

Vous pouvez le vérifier :

```
grep -rn 'AX[A-Za-z]*(' Sources/
```

Le seul verbe est `Set`, sur un seul attribut, qui prend une valeur booléenne :
la même chose que ⌘H sur l'app. Le pid ciblé est toujours celui d'une app que
Bouncer a détectée dans l'encoche, jamais un autre.

Un détail qui va dans le même sens : l'app refuse d'appeler l'API AX tant que
l'autorisation n'est pas accordée (`WindowManager.swift:316`). Une app qui
voudrait tâter le terrain ferait l'inverse.

### Le README surestime ce que l'autorisation apporte

`README.md:109` affirme que l'Accessibilité est indispensable « pour interroger
la liste des fenêtres du WindowServer (`CGWindowList`), capter les mouvements sur
la zone d'encoche et piloter le masquage ». C'est vrai du troisième point
seulement.

`CGWindowListCopyWindowInfo`, avec les options qu'utilise Bouncer, rend les pid,
les dimensions et les niveaux de fenêtre sans aucune autorisation ; seuls les
titres de fenêtre exigent l'autorisation Enregistrement de l'écran, que Bouncer
ne demande pas. Les monitors `NSEvent` de mouvement de souris et de défilement
n'exigent rien non plus : ce sont les événements clavier qui réclament
l'Accessibilité, et Bouncer n'en écoute aucun.

Le code le montre : `refresh()` tourne dans le constructeur
(`WindowManager.swift:131`) avant tout octroi d'autorisation, et la fenêtre
d'accueil affiche les apps détectées pendant que vous n'avez encore rien
accordé. La détection marche sans l'Accessibilité. **Le masquage, lui, ne marche
pas sans elle** — c'est la seule raison de la demander.

## 4. Ce que Bouncer voit dans la liste des fenêtres

`CGWindowListCopyWindowInfo` rend une entrée par fenêtre à l'écran, toutes
applications confondues. Bouncer l'appelle avec
`[.optionOnScreenOnly, .excludeDesktopElements]` (`WindowManager.swift:218-220`
et `ControleurApps.swift:259-261`) et lit exactement quatre champs :

- `kCGWindowOwnerPID` — l'identifiant du processus propriétaire
- `kCGWindowBounds` — la position et la taille de la fenêtre
- `kCGWindowLayer` — son niveau d'empilement
- `kCGWindowOwnerName` — le nom de l'**application** (« Finder », « Discord »)

`kCGWindowName`, qui porte le **titre** de la fenêtre, n'apparaît nulle part
dans le code. Bouncer ne le lit pas, ne le stocke pas, ne l'affiche pas. Et il ne
lui serait de toute façon pas rendu : sans autorisation Enregistrement de
l'écran, macOS omet ce champ.

Ce que Bouncer garde de ce balayage est étroit. Chaque entrée passe par trois
filtres avant d'être retenue (`ControleurApps.swift:139-158`) : la fenêtre doit
toucher le bord haut de l'écran, recouvrir entièrement le boîtier caméra, et ne
pas occuper plus de 80 % de la largeur de l'écran. Une fenêtre de document
normale, une fenêtre plein écran, une icône de barre de menus sont toutes
recalées. Ce qui survit est écrit au catalogue sous forme d'un bundleID
(`WindowManager.swift:301-303`), et rien d'autre : ni le nom d'affichage, ni la
géométrie, ni le pid, qui restent en mémoire le temps de la session.

Le nom d'affichage lu en `WindowManager.swift:236` sert à l'affichage du menu et
n'est jamais persisté ; le code choisit délibérément le bundleID comme identité,
parce qu'un nom suit la langue du système (`WindowManager.swift:41-43`).

Bouncer s'exclut elle-même du balayage (`WindowManager.swift:234`) et ignore huit
processus système par bundleID (`WindowManager.swift:44-48`).

## 5. Ce que Bouncer observe de vos gestes

Deux monitors globaux d'événements, dans `NotchOverlay.swift` :

- **Mouvements de souris** (`:89`) : attaché en permanence tant que l'app tourne.
  Le callback jette l'événement (`{ [weak self] _ in }`) et lit seulement
  `NSEvent.mouseLocation` pour savoir si le curseur approche de l'encoche.
- **Molette et défilement trackpad** (`:197`) : attaché **uniquement** quand le
  mode swipe est actif et que le curseur est déjà dans la bande d'encoche
  (`:190`), détaché dès qu'il en sort (`:200-202`). De l'événement, Bouncer lit
  la phase du geste, l'inertie, deux deltas et un horodatage
  (`Swipe.swift:20-30`).

**Aucun monitor clavier.** Ni `.keyDown`, ni `.flagsChanged`, ni `CGEventTap`.
Aucun accès au presse-papiers, à la caméra, au micro, à la localisation, aux
contacts, au calendrier, ni à la capture d'écran : le grep correspondant ne
remonte rien.

Ces monitors sont « globaux » au sens d'AppKit, ce qui veut dire qu'ils observent
sans consommer : Bouncer ne peut ni bloquer ni modifier un événement destiné à
une autre app. Le monitor de défilement doit être global parce qu'une app
d'encoche tierce consomme le scroll avant nous dès qu'elle déploie son panneau
(`NotchOverlay.swift:183-185`).

## 6. La signature, sans enjoliver

Bouncer n'a pas de Developer ID Apple et n'est pas notarisée. Le programme
Developer coûte 99 €/an et le projet ne le paie pas.

Le binaire est signé par un **certificat auto-signé généré sur la machine du
développeur** (`build.sh:60-80`), avec le nom commun `Bouncer Local Signing`. Sur
votre Mac, ce certificat n'est pas de confiance et ne le sera jamais. Ce que
cette signature vous donne et ne vous donne pas :

**Ce qu'elle fait.** Elle rend l'app identifiable de façon stable entre deux
versions. La designated requirement embarquée est une comparaison de hash de
feuille (`build.sh:9-11`, mesuré et détaillé dans `docs/DISTRIBUTION.md:196-207`) :

```
identifier "io.github.donpaco13.bouncer"
and certificate leaf = H"30b31538…"
```

C'est ce qui permet à l'autorisation Accessibilité de survivre à une mise à jour
sans que vous ayez à la redonner.

**Ce qu'elle ne fait pas.** Elle ne prouve rien sur l'identité de l'auteur, et
Apple n'a jamais examiné ce binaire. Gatekeeper le rejette, et
`docs/DISTRIBUTION.md:66-73` montre le verdict mesuré :

```
$ spctl --assess --type execute -vv Test.app
Test.app: rejected
origin=Bouncer Local Signing
```

La signature est valide et l'app n'est pas corrompue ; c'est le distributeur qui
n'est pas reconnu.

**Ce que fait l'installation Homebrew.** Le cask retire l'attribut de quarantaine
juste après l'installation (`Casks/bouncer.rb:22-25`). Homebrew a supprimé
l'option `--no-quarantine` en juillet 2026 précisément pour empêcher ce
contournement côté utilisateur, et le cask le réintroduit côté auteur. Le
commentaire du fichier l'assume en toutes lettres. Conséquence pratique : **si
vous installez par `brew`, vous ne verrez jamais l'avertissement Gatekeeper**,
et vous n'aurez pas eu l'occasion de le refuser. Si vous préférez le voir,
téléchargez l'archive `.zip` de la page des versions et laissez macOS vous poser
la question.

**Il n'y a pas de bac à sable.** Bouncer n'est pas sandboxée, ne demande pas de
Hardened Runtime, et n'embarque aucun fichier d'entitlements : l'`Info.plist`
écrit par `build.sh:25-52` ne contient que du descriptif de bundle. Rien au
niveau du système n'**empêche** techniquement Bouncer d'ouvrir une connexion
réseau, avec ou sans la case cochée. La garantie de la section 1 est une
garantie de code lu, pas une garantie imposée par macOS. C'est pour ça que le code est public, que les
lignes sont citées, et que les commandes de vérification sont écrites plus haut.

## 7. Ce que l'audit a trouvé de gênant

Cinq points, du plus au moins sérieux.

**1. Pendant un mois, Sentry démarrait sans vous demander.** Du commit
`b121105` (16 septembre 2026) au commit `a7f0eec` (13 octobre 2026), le SDK
était démarré à chaque lancement, suivi de sessions compris, alors que ce
document affirmait « aucun code réseau, aucune dépendance tierce ». Une app
compilée sur cette période envoyait un signal à chaque lancement et un rapport
à chaque plantage. Depuis `a7f0eec`, rien ne part sans la case cochée. Si vous
avez fait tourner une de ces versions, les dossiers de cache listés en section 1
sont sur votre disque et peuvent être supprimés.

**2. L'installation Homebrew désactive Gatekeeper pour vous.** Détaillé en
section 6. C'est le seul endroit où Bouncer décide à votre place de sauter une
vérification de sécurité de macOS. Le contournement est visible dans le cask et
documenté, mais il s'exécute sans vous demander votre avis.

**3. Le catalogue d'apprentissage ne s'oublie pas.** `bouncer.bundleIDsApprises.v2`
grossit sans jamais rétrécir : aucune interface ne permet d'en retirer une entrée,
et le code n'offre aucune suppression sélective. Une app désinstallée sort de la
liste affichée mais reste dans le fichier (`CatalogueApps.swift:89-90`). Le seul
moyen de repartir de zéro est de supprimer le plist à la main. La liste est
courte et ne contient que des bundleIDs d'apps d'encoche, mais c'est une trace
persistante que vous ne pouvez pas effacer depuis l'app.

**4. Deux documents du dépôt sont périmés sur ce sujet.** Le commentaire de
`Casks/bouncer.rb:29-31` annonce « deux clés » de préférences ; il y en a huit.
`docs/DISTRIBUTION.md:150` propose de nettoyer `~/Library/Application
Support/Bouncer`, un dossier que l'app ne crée jamais. Sans conséquence
pratique, puisque le `zap` du cask jette le plist entier. Mais un lecteur qui se
fierait à ces commentaires aurait une image incomplète.

**5. Le README surestime le rôle de l'autorisation.** Détaillé en section 3. Il
attribue à l'Accessibilité la détection des fenêtres et la capture des gestes,
qui marchent sans elle. L'app justifie donc sa demande par plus de choses qu'elle
n'en tire — l'erreur penche du côté de la sur-justification, pas de la
sur-collecte.

Rien d'autre n'est ressorti : pas de télémétrie, pas de lecture de contenu
d'application, pas d'écriture de fichier hors des préférences et du cache Sentry
décrit en section 1, pas d'écoute clavier.

## 8. Refaire l'audit vous-même

Le dépôt entier fait environ 2 800 lignes de Swift. Les quatre commandes qui
fondent ce document :

```
grep -rniE 'URLSession|CFNetwork|NWConnection|socket|WKWebView|http|SentrySDK' Sources/
grep -rn 'AX[A-Za-z]*(' Sources/
grep -rn 'kCGWindow' Sources/
grep -rnE 'UserDefaults|FileManager|\.write\(|OSLog|NSLog' Sources/
```

Et pour voir ce que Bouncer détecte sur votre machine, sans lancer l'interface :

```
/Applications/Bouncer.app/Contents/MacOS/Bouncer --self-test
```

Il imprime l'état de l'autorisation, la zone d'encoche et la liste des apps
détectées, puis quitte (`main.swift:10-28`).

Si vous trouvez une erreur dans ce document, ouvrez une issue : une affirmation
fausse ici est plus grave qu'un bug dans l'app.
