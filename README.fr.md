<h1 align="center">Bouncer</h1>

<p align="center"><b>Une encoche, une app à la fois.</b></p>

<p align="center">
  <a href="https://github.com/donpaco13/Bouncer/actions/workflows/ci.yml"><img src="https://github.com/donpaco13/Bouncer/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://github.com/donpaco13/Bouncer/releases/latest"><img src="https://img.shields.io/github/v/release/donpaco13/Bouncer?label=download&color=brightgreen" alt="Télécharger"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/donpaco13/Bouncer" alt="Licence"></a>
</p>

<p align="center"><a href="README.md">Read in English</a></p>

Bouncer décide quelle app d'encoche vous voyez sur votre MacBook. Vibe Island, boringNotch
et les autres restent installées et ouvertes ; une seule s'affiche, et vous changez d'avis
d'un balayage à deux doigts sur l'encoche, d'un clic sur une flèche, d'un raccourci clavier
ou depuis la barre des menus.

C'est pour les gens qui ont un MacBook à encoche, plusieurs apps d'encoche, et qui en ont
assez de quitter l'une pour voir l'autre.

<!-- TODO : le GIF de démonstration d'une bascule (swipe sur l'encoche, l'app A cède la place à l'app B) vient ici. -->

## Pourquoi elle existe

Chaque app d'encoche dessine sa propre pastille sous l'encoche. Ouvrez-en deux et elles
atterrissent sur le même rectangle, l'une par-dessus l'autre. macOS ne coordonne rien :
la notion d'« app d'encoche active » n'existe pas au niveau du système, et la seule issue
qu'il vous laisse consiste à quitter une app puis à la relancer quand vous en avez besoin.

## Installation

Bouncer se distribue depuis sa [page des releases](https://github.com/donpaco13/Bouncer/releases).
Le badge de téléchargement en haut de cette page donne la version courante, et affiche
`no releases` tant qu'aucune n'est publiée ; quoi qu'il affiche, la compilation depuis les
sources, plus bas, marche à n'importe quel commit.

### Homebrew

```bash
brew install --cask donpaco13/tap/bouncer
```

Bouncer arrive dans `/Applications` et s'ouvre normalement. Le cask retire lui-même
l'attribut de quarantaine, vous ne voyez donc jamais l'écran ci-dessous.

### Téléchargement de l'archive

1. Récupérez la dernière `Bouncer-x.x.x.zip` sur la [page des releases](https://github.com/donpaco13/Bouncer/releases).
2. Décompressez-la.
3. Glissez `Bouncer.app` dans `/Applications`.

### « macOS n'a pas pu vérifier que Bouncer ne contient pas de logiciel malveillant »

C'est ce qu'affiche le premier lancement si vous êtes passé par l'archive, et c'est normal.
macOS ne sait pas qui a écrit Bouncer : Apple facture aux développeurs 99 € par an une
identité qu'il reconnaît à vue, et le projet ne la paie pas. Le binaire est signé par un
certificat auto-signé local (`Bouncer Local Signing`). Le blocage porte sur cette identité
manquante, pas sur le contenu de l'app.

Pour l'ouvrir quand même, une fois :

1. Double-cliquez sur Bouncer et laissez macOS refuser.
2. Ouvrez **Réglages Système** > **Confidentialité et sécurité**.
3. Descendez jusqu'au message concernant Bouncer et cliquez sur **Ouvrir quand même**.
4. Confirmez avec votre mot de passe.

Les lancements suivants passent directement.

### Compilation depuis les sources

Il faut macOS 14+ et les Xcode Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/donpaco13/Bouncer.git
cd Bouncer
./build.sh
```

`build.sh` compile en release avec SwiftPM, assemble `Bouncer.app`, crée dans votre
trousseau une identité de signature locale persistante pour que l'autorisation Accessibilité
survive d'une compilation à l'autre, installe le bundle dans `/Applications` et le lance.

Pour voir ce que Bouncer trouve sous votre encoche sans ouvrir l'interface :

```bash
"/Applications/Bouncer.app/Contents/MacOS/Bouncer" --self-test
```

## Ce qu'il vous faut

- **macOS 14 Sonoma ou plus récent.** Les API de cycle de vie et l'interface sont écrites pour ces versions.
- **Un MacBook à encoche matérielle** (`safeAreaInsets.top > 0`) : MacBook Pro 14 et 16 pouces Apple Silicon, MacBook Air 13 et 15 pouces M2/M3/M4. Avec un écran externe en principal, Bouncer retrouve tout seul l'écran intégré qui porte l'encoche.
- **L'autorisation Accessibilité** (`AXIsProcessTrusted`), demandée au premier lancement. C'est elle qui permet à Bouncer de lire la liste des fenêtres et de masquer celles des autres apps. Sans elle, Bouncer ne touche à rien.
- **Au moins une app d'encoche tierce.** Bouncer est un régisseur, pas un widget d'encoche. Sans rien d'installé il n'a rien à arbitrer, et le guide de démarrage vous le dit.

## Changer d'application

Quatre moyens, tous équivalents : avancer d'un cran dans le cycle, qui tourne en boucle.

- **Le swipe sur l'encoche.** Placez le curseur sur la surface de l'app d'encoche et balayez horizontalement à deux doigts. Gauche ou droite ne change rien, le geste avance d'un cran.
- **Les flèches au survol.** Approchez la souris du boîtier caméra, deux flèches (‹ et ›) apparaissent de part et d'autre. Cliquez sur l'une. Hors survol, Bouncer ne dessine rien.
- **Le raccourci global.** `⌃⌥⌘B` marche depuis n'importe quelle app, plein écran compris. Sans trackpad, c'est la seule commande qui n'oblige ni à viser l'encoche ni à ouvrir un menu.
- **La barre des menus.** `●` désigne l'app qui occupe l'encoche, `○` une app en attente (cliquez dessus pour la ramener, ouverte ou fermée), `◐` une bascule en cours. Chaque entrée précise en infobulle si la bascule sera instantanée ou par relance.

Bouncer n'a pas d'icône dans le Dock ni de fenêtre à gérer (`LSUIElement = true`). Au premier
lancement, il ouvre un guide en cinq écrans qui vérifie l'autorisation Accessibilité en
direct et vous fait essayer le geste ; vous pouvez le rouvrir depuis le menu.

## Ce qui se passe pendant une bascule

Deux voies, choisies automatiquement selon ce que le binaire de chaque app accepte. Rien à régler.

1. **Le masquage (environ 31 ms).** Pour les apps qui laissent leurs fenêtres dans le Space utilisateur standard, Bouncer applique l'attribut d'Accessibilité `kAXHiddenAttribute`. L'app reste en mémoire, garde son état et revient en 5 ms sans redémarrer.
2. **La relance (environ 1 s).** Pour les apps qui créent leur propre Space privé auprès du WindowServer (`CGSSpaceCreate` + `CGSAddWindowsToSpaces`) et ignorent l'ordre de masquage, Bouncer démarre la cible, attend que sa fenêtre apparaisse sous l'encoche, puis ferme l'ancienne.

| Application | Voie | Mesuré |
|---|---|---|
| **Vibe Island** | Masquage | 31,7 ms à l'aller, 5,1 ms au retour. Reste en mémoire. |
| **boringNotch** | Relance | Environ 1 s. L'ancienne instance ferme dès que la nouvelle fenêtre est visible. |

Le recensement complet des apps d'encoche du marché, mesure et prédiction séparées, est dans
[`docs/COMPATIBILITE.md`](docs/COMPATIBILITE.md).

Deux garanties tiennent sur les deux voies :

- **Allumer avant d'éteindre.** Bouncer ne masque ni ne ferme l'app en place tant que la nouvelle fenêtre n'a pas été recomptée à l'écran par `CGWindowList`, et non déduite du code de retour d'une API. Si la cible ne démarre pas, ou tarde plus de cinq secondes, l'app en place ne bouge pas. Vous ne vous retrouvez jamais avec une encoche vide, ni avec deux processus tués.
- **Un filtre géométrique strict.** Pour qu'une fenêtre haute de navigateur ou de Discord ne passe jamais pour une app d'encoche, une fenêtre doit être flottante (`layer > 0`), collée au bord supérieur de l'écran, et assez large pour couvrir le boîtier caméra sans occuper tout l'écran (moins de 80 % de sa largeur).

## Les réglages

`⌘,` ouvre trois onglets. **Général** contient le lancement à l'ouverture de session et la
fréquence de resondage des fenêtres (1 à 30 secondes, 2 par défaut). **Geste** contient le
mode d'activation, le raccourci global, la zone sensible et la géométrie des flèches de
survol. **Applications** liste tout ce que Bouncer reconnaît ; décocher une app la sort du
cycle de balayage tout en la laissant cliquable dans le menu.

## Hors périmètre

- **Aucune API privée instable.** Ni `CGSSetWindowAlpha`, ni injection WindowServer non documentée qui casserait à la prochaine mise à jour mineure de macOS.
- **Pas de vue partagée.** Bouncer ne dessine pas deux apps côte à côte dans l'encoche et ne capture pas leur rendu.
- **Pas de version Mac App Store.** Le bac à sable qu'impose le store bloque l'API Accessibilité, c'est-à-dire tout le moteur.

## Contribuer

Les issues et les pull requests sont bienvenues, en français comme en anglais. Le code source
est écrit en français (types, méthodes, commentaires) : alignez-vous sur le fichier autour
plutôt que de le traduire.

```bash
swift build
swift test
```

La CI fait tourner les deux sur macOS avec Xcode 16.4. Une modification du comportement de
bascule s'accompagne de la mesure qui la justifie, comme le font
[`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) et [`docs/COMPATIBILITE.md`](docs/COMPATIBILITE.md).

## Documentation

- [`docs/COMPATIBILITE.md`](docs/COMPATIBILITE.md) : chaque app d'encoche recensée, et le verdict de Bouncer pour chacune.
- [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) : Gatekeeper, quarantaine Homebrew et signatures.
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) : coût CPU, prix d'un scan `CGWindowList`, et ce qui a été optimisé.
- [`docs/CONFIDENTIALITE.md`](docs/CONFIDENTIALITE.md) : ce que Bouncer lit, ce qu'il stocke, ce qu'il n'envoie jamais.
- [`docs/archive/`](docs/archive/) : les spikes de validation d'origine et les documents d'architecture.

## Licence

[MIT](LICENSE).
