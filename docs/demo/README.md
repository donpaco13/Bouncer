# Filmer Bouncer

Le README et la landing attendent une démonstration de la bascule. Personne ne l'a
produite jusqu'ici, et ce dossier existe pour que la prochaine tentative ne
recommence pas l'enquête.

## La cause n'est pas celle que le dépôt a retenue

Le dépôt a retenu que `screencapture` n'inclut pas les fenêtres de niveau 35, celui
de l'overlay (`NotchOverlay.swift`, `statusBar + 10`), et plusieurs agents y ont perdu
du temps.
**C'est faux, ou en tout cas ça n'a jamais été démontré.** Mesuré le 7 septembre 2026
sur macOS 15.7.9, depuis un agent lancé par Munder Difflin :

| Voie | Résultat |
|---|---|
| `screencapture -x -o` (image fixe) | Rend un PNG, mais **sans aucune fenêtre**, à tous les niveaux : ni l'overlay (35), ni les icônes de statut (25), ni les fenêtres d'apps (0). Seuls le fond d'écran et la barre des menus sortent. |
| `screencapture -v` (vidéo) | `capture error : L'opération n'a pas pu être effectuée`. Échoue avant d'écrire quoi que ce soit. |
| ScreenCaptureKit (`SCShareableContent`) | `SCStreamErrorDomain Code=-3801`, TCC refusé. `CGPreflightScreenCaptureAccess()` renvoie `false`. |
| `CGWindowListCreateImage` | **Obsolète depuis macOS 15.0** : ne compile plus. La voie n'existe plus, indépendamment des autorisations. |

Une capture qui perd aussi les fenêtres de niveau 0 ne dit rien sur le niveau 35.
Les trois premières lignes nomment la vraie cause : le processus n'a pas
l'autorisation **Enregistrement de l'écran**.

Le niveau 35 n'a rien de spécial pour le serveur de fenêtres non plus :
`CGWindowListCopyWindowInfo` liste un `NSPanel` de niveau 35 avec ses bornes, à côté
de la barre des menus et des icônes de statut.

## Ce qui reste à vérifier une fois l'autorisation accordée

Que le niveau 35 sorte bien dans une capture autorisée n'a pas pu être mesuré, faute
de cette autorisation. C'est la première chose à regarder, et une seule image suffit
à trancher.

## La marche à suivre

Un agent ne peut pas s'accorder l'autorisation lui-même. Le réglage est un
interrupteur système, et donner à un hôte d'agents un accès permanent à l'écran se
décide en connaissance de cause.

1. **Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran.**
   Activer l'app qui lancera l'enregistrement : Munder Difflin pour un agent, le
   Terminal ou QuickTime sinon.
2. **Enregistrer.** ⇧⌘5, « Enregistrer une partie sélectionnée », un bandeau qui
   couvre l'encoche et déborde de quelques centimètres de chaque côté. Puis jouer la
   bascule : approcher le curseur pour révéler les chevrons, faire le geste, laisser
   l'app suivante prendre la place.
3. **Encoder.**
   ```sh
   ./docs/demo/encoder.sh ~/Desktop/capture.mov
   # ou, pour recadrer (en PIXELS de la source ; Retina = 2x les points écran) :
   ./docs/demo/encoder.sh ~/Desktop/capture.mov 2704:400:0:0
   ```
   Sort `docs/demo/demo.webp` (README) et `docs/demo/demo.mp4` (landing).

Le script tourne à 880 px de large et 20 im/s. Sur une source de bruit pur, le pire
cas pour un compresseur, 8 secondes donnent 418 Ko en WebP et 85 Ko en MP4. Un
enregistrement d'écran, presque entièrement statique, tient bien en dessous.

## Où va l'asset

- **README.md / README.fr.md** : remplacer le `<!-- TODO: demo GIF -->` par
  `![](docs/demo/demo.webp)`. GitHub anime le WebP, et il pèse le cinquième du GIF
  équivalent.
- **Landing** : `demo.mp4` dans un `<video autoplay muted loop playsinline>`.
  Un MP4 se décode matériellement, un WebP animé non.

Garder le bandeau serré autour de l'encoche : le contenu du reste de l'écran n'ajoute
rien et fait grossir le fichier. Filmer sur un fond d'écran neutre — la barre des
menus suit l'apparence système, donc la même prise reste lisible en clair comme en
sombre.
