# Contribution préparée pour boringNotch

Objectif : donner à boringNotch un point d'entrée public pour masquer et
réafficher sa pilule, pour qu'elle devienne un deuxième candidat régissable par
Bouncer (aujourd'hui il n'y a que Vibe Island, ce qui empêche de démontrer la
feature centrale du produit).

**Rien n'a été poussé nulle part.** Forker, pousser et ouvrir une PR sur le
dépôt d'un tiers est une action publique au nom de François — elle lui revient.
Ce dossier contient tout ce qu'il faut pour n'avoir qu'à valider.

## Fichiers

| Fichier | Quoi |
| --- | --- |
| `ISSUE.md` | Le draft d'issue à ouvrir **en premier** (le CONTRIBUTING l'exige pour une feature) |
| `PR.md` | Titre + corps de la PR, prêt à coller |
| `0001-add-a-way-to-hide-and-show-the-notch.patch` | Le commit, en `git format-patch` |

## Ce que fait le patch

Une seule primitive, `setNotchHidden(_:)` dans `AppDelegate`, qui fait
`orderOut(nil)` / `orderFrontRegardless()` sur toutes les fenêtres de la pilule.
Trois surfaces l'appellent :

1. un item **Hide/Show Notch** dans le menu de la barre de menus ;
2. un raccourci clavier (sans binding par défaut) dans Settings → Shortcuts ;
3. un **URL scheme `boringnotch://`** avec `hide`, `show`, `toggle`.

C'est le point 3 qui nous intéresse : Bouncer pilotera boringNotch avec
`open -g "boringnotch://hide"` — pas d'API privée, pas d'Accessibility, pas de
permission à demander.

89 lignes ajoutées, 4 fichiers, aucune dépendance nouvelle, aucune traduction
touchée.

Détail qui compte : `createBoringNotchWindow` consulte le flag avant
`orderFrontRegardless()`. Sans ça, chaque chemin qui recrée les fenêtres
(branchement d'un écran, verrouillage écran avec *Show on lock screen* off,
bascule *Show on all displays*) ferait réapparaître la pilule masquée.

Le patch réanime aussi `togglePopover(_:)`, code mort jamais appelé qui ne
gérait que le mode mono-écran.

## Application du patch

```bash
git clone https://github.com/<ton-fork>/boring.notch.git
cd boring.notch
git checkout dev
git checkout -b feature/notch-visibility-control
git am /chemin/vers/0001-add-a-way-to-hide-and-show-the-notch.patch
```

Le commit est basé sur `origin/dev` à `efd3470` (« Merge pull request #1477 »).
Si `dev` a bougé, `git am -3` ou un rebase.

## Ce qui reste à vérifier — à faire avant d'ouvrir la PR

**Le patch n'a pas été compilé.** L'Xcode installé sur cette machine est 16.4
(Swift 6.1) et les dépendances épinglées du projet (`Defaults` 9.0.9,
`KeyboardShortcuts` 3.0.1) réclament Swift tools 6.2, donc Xcode 26 :

```
xcodebuild: error: Could not resolve package dependencies:
  package 'defaults' @ 9.0.9 is using Swift tools version 6.2.0 but the installed version is 6.1.0
```

Ce qui a été vérifié : `swiftc -parse` passe sur les trois fichiers Swift
modifiés, `plutil -lint` passe sur l'`Info.plist`. C'est de la syntaxe, pas du
type-check et pas du runtime.

Donc, avec un Xcode 26 :

1. Builder.
2. Dérouler le protocole de test listé dans la section *Testing* de `PR.md`, et
   remplacer cette section par ce qui a réellement été observé.
3. Capturer une vidéo ou des captures du menu bar item — le template de PR
   du dépôt les exige.
4. Ouvrir l'issue depuis `ISSUE.md`, récupérer son numéro, le mettre dans
   `PR.md` à la place de `#XXXX`.
5. Ouvrir la PR **sur `dev`**.

## Points d'incertitude honnêtes

- `orderOut(nil)` sur une fenêtre épinglée dans un Space CGS privé : la lecture
  du code dit que ça doit marcher (`orderOut` démappe la fenêtre au niveau du
  WindowServer, indépendamment du Space), et le `togglePopover` mort d'origine
  faisait exactement ça. Non prouvé à l'exécution faute de build.
- Le `Button` du menu bar suit `isNotchHidden` via `@Published` sur
  l'`AppDelegate`, qui devient `ObservableObject`. `@NSApplicationDelegateAdaptor`
  observe bien un delegate `ObservableObject`, mais ce chemin n'a pas été
  exécuté.
- Sous App Sandbox (le projet l'active), recevoir une URL entrante passe par
  LaunchServices et n'est pas restreint. C'est aussi la raison pour laquelle
  l'URL scheme a été choisi plutôt qu'une notification distribuée, que le bac à
  sable filtre entre applis tierces.

## Contexte amont

- Issue #1176 « [FEATURE] Automatically disappearing notch on NON notch macs »
  demande explicitement « be able to hide it with a key combination ». Le
  raccourci clavier du patch répond à cette moitié — d'où l'intérêt de la
  mentionner dans la PR plutôt que d'arriver avec un besoin qui n'intéresse
  que nous.
- Issue #1278 « [FEATURE] Hide the notch when fullscreen » pourrait se poser
  au-dessus de la même primitive.
- Aucune issue ni PR existante ne demande un URL scheme de contrôle (recherche
  API GitHub sur `url scheme`, `hide notch`, `applescript`, `shortcuts intent`).
