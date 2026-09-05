# Bouncer

[![CI](https://github.com/donpaco13/Bouncer/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/donpaco13/Bouncer/actions/workflows/ci.yml)

Sur un MacBook équipé d'une encoche matérielle, deux applications de notch ouvertes en même temps dessinent au même endroit et se superposent. macOS ne coordonne rien : aucune notion d'« app d'encoche active » n'existe au niveau du système. La seule issue manuelle consiste à quitter l'une pour voir l'autre.

Bouncer résout ce conflit en régissant la visibilité des applications d'encoche : une seule application occupe le notch à la fois. Vous passez de l'une à l'autre d'un geste sur le trackpad, d'un clic sur des flèches au survol, d'un raccourci clavier global, ou depuis la barre des menus.

L'utilitaire s'adresse aux utilisateurs de MacBook à encoche (M1 Pro/Max, M2, M3, M4) combinant plusieurs outils dédiés (monitoring d'agents, widgets audio, calendrier ou système comme Vibe Island et boringNotch).

---

## 1. Ce que fait Bouncer

Bouncer maintient un catalogue des applications de notch installées sur votre Mac. Quand vous demandez une bascule, elle orchestre le passage de l'application active vers l'application suivante selon deux méthodes, choisies automatiquement selon ce que chaque binaire accepte :

1. **La voie rapide (masquage instantané, ~31 ms)** : pour les applications qui laissent leurs fenêtres dans le Space utilisateur standard (comme Vibe Island). Bouncer applique l'attribut d'Accessibilité `kAXHiddenAttribute`. L'application reste active en mémoire, conserve son état et se réaffiche en 5 ms sans redémarrer.
2. **La voie par cycle de vie (relance, ~1 s)** : pour les applications qui créent leur propre Space privé auprès du WindowServer (`CGSSpaceCreate` + `CGSAddWindowsToSpaces`, comme boringNotch) et ignorent l'ordre de masquage. Bouncer démarre la cible, attend que sa fenêtre apparaisse sous l'encoche, puis ferme l'ancienne.

### Les garanties du moteur

- **Allumer avant d'éteindre** : Bouncer ne masque ou ne ferme l'application précédente qu'une fois la nouvelle fenêtre confirmée à l'écran par recomptage `CGWindowList`. Si l'application cible ne démarre pas ou tarde plus de 5 secondes, l'application actuelle reste intacte. Vous ne vous retrouvez jamais avec une encoche vide ou deux processus tués.
- **Filtre géométrique strict** : pour ne pas confondre une vraie app d'encoche avec une fenêtre haute (navigateur, Discord ou Finder), Bouncer impose trois critères physiques réels : fenêtre flottante (`layer > 0`), sommet collé au bord supérieur de l'écran, et largeur recouvrant le boîtier caméra matériel sans déborder sur l'écran entier (< 80 % de la largeur).
- **Survie aux redémarrages** : le catalogue mémorise les applications déjà vues sous l'encoche. Une application fermée reste listée dans le menu et peut être relancée d'un clic ou par le geste de bascule.

### État de prise en charge des applications

| Application | Méthode de bascule | Comportement mesuré |
|---|---|---|
| **Vibe Island** | Masquage Accessibilité (voie rapide) | Masquage en 31,7 ms, réaffichage en 5,1 ms. L'application reste en mémoire. |
| **boringNotch** | Cycle de vie (relance) | Relance en ~1 s. L'ancienne instance est fermée dès que la nouvelle fenêtre est visible. |

Les rapports d'analyse statique et de mesure détaillés sont conservés dans [`docs/archive/SPIKE_RESULTS.md`](docs/archive/SPIKE_RESULTS.md).

---

## 2. Comment l'installer

### Via Homebrew (recommandé)

```bash
brew install --cask donpaco13/tap/bouncer
```

Le Cask Homebrew installe Bouncer dans votre dossier `/Applications` et retire automatiquement l'attribut de quarantaine au premier déploiement.

### Téléchargement manuel (.zip)

1. Téléchargez la dernière archive `Bouncer-x.x.x.zip` depuis la [page des Releases](https://github.com/donpaco13/Bouncer/releases).
2. Décompressez l'archive.
3. Glissez `Bouncer.app` dans votre dossier `/Applications`.
4. Consultez la section [Honnêtement, ce qu'elle n'est pas](#5-honnêtement-ce-quelle-nest-pas) pour le premier lancement.

### Compilation depuis les sources

Prérequis : macOS 14.0+, Xcode Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/donpaco13/Bouncer.git
cd Bouncer
./build.sh
```

Le script `build.sh` compile le binaire en configuration release via SwiftPM, génère le bundle `Bouncer.app`, crée une identité de signature locale persistante dans votre trousseau (pour conserver l'autorisation Accessibilité d'une compilation à l'autre sans dérive de signature ad-hoc), installe le bundle dans `/Applications` et lance l'application.

Pour vérifier l'état du système sans interface graphique :

```bash
"/Applications/Bouncer.app/Contents/MacOS/Bouncer" --self-test
```

---

## 3. Comment on s'en sert

Bouncer est un utilitaire d'arrière-plan sans icône dans le Dock (`LSUIElement = true`). Il réside dans la barre des menus, en haut à droite de l'écran.

### Le guide de démarrage

Au tout premier lancement, Bouncer affiche automatiquement une fenêtre de bienvenue qui :
- Vous indique son emplacement dans la barre des menus.
- Vérifie l'état de l'autorisation Accessibilité (mise à jour réactive sans avoir à relancer l'app dès que vous l'accordez).
- Présente le geste physique de commande.

Vous pouvez rouvrir ce guide à tout moment via l'entrée « Guide de démarrage… » du menu.

### Les gestes de commande

- **Le swipe sur l'encoche (aucun sens à retenir)** : placez le curseur sur l'île — toute la surface de l'application d'encoche répond, pas seulement la bande de l'encoche matérielle — et effectuez un balayage horizontal à deux doigts sur le trackpad. Que votre geste aille vers la gauche ou vers la droite, il fait avancer d'un cran dans le cycle des applications. Répéter le geste fait tourner toutes vos applications en boucle continue.
- **Les flèches au survol** : deux flèches discrètes (‹ et ›) apparaissent de part et d'autre du boîtier de la caméra lorsque le curseur approche de l'encoche. Cliquez sur la flèche gauche ou droite pour changer d'application.
- **Le raccourci clavier global** : `⌃⌥⌘B` avance d'un cran dans le cycle, exactement comme le swipe, depuis n'importe quelle application et y compris en plein écran. Sans trackpad, c'est la seule commande qui n'oblige ni à viser l'encoche ni à ouvrir un menu. La combinaison se change ou se désactive dans **Réglages > Geste** ; tant que Bouncer tourne, elle n'atteint plus les autres applications.
- **Le menu de la barre des menus** :
  - `●` indique l'application qui occupe actuellement l'encoche.
  - `○` indique une application en attente (cliquer dessus pour la basculer, qu'elle soit ouverte ou fermée).
  - `◐` indique une bascule en cours.
  - Une infobulle sur chaque entrée précise si la bascule sera instantanée ou par relance.

### Les Réglages (⌘,)

Ouvrez les réglages depuis le menu de l'app ou avec le raccourci `⌘,` :

- **Général** : activation du lancement automatique à l'ouverture de session macOS, et fréquence de resondage des fenêtres (de 1 à 30 secondes, 2 secondes par défaut).
- **Geste** : choix du mode d'activation (le swipe et les flèches, le swipe seul sans overlay visuel, ou les flèches seules pour un usage à la souris), raccourci clavier global (`⌃⌥⌘B`, `⌃⌥⌘N`, `⌃⌥⌘Espace` ou aucun), zone sensible (la fenêtre de l'app d'encoche, ou le boîtier caméra seul), portée d'apparition des flèches à l'approche (72 pt par défaut), amplitude de leur déploiement (8 pt par défaut), et largeur de la marge cliquable (44 pt par défaut).
- **Applications** : liste de toutes les applications reconnues. Décocher une application la retire du cycle de balayage au trackpad tout en la laissant sélectionnable au clic dans le menu.

---

## 4. Ce qu'elle exige

1. **macOS 14.0 (Sonoma) ou version ultérieure** : requis pour les API modernes de gestion de cycle de vie et l'interface SwiftUI.
2. **Un MacBook doté d'une encoche matérielle** : écran Liquid Retina avec `safeAreaInsets.top > 0` (MacBook Pro 14" et 16" Apple Silicon, MacBook Air 13" et 15" M2/M3/M4). Si vous utilisez un écran externe comme moniteur principal, Bouncer détecte automatiquement l'écran intégré portant l'encoche.
3. **L'autorisation Accessibilité (`AXIsProcessTrusted`)** : indispensable pour interroger la liste des fenêtres du WindowServer (`CGWindowList`), capter les mouvements sur la zone d'encoche et piloter le masquage des applications tierces.
4. **Au moins une application d'encoche tierce installée** : Bouncer est un régisseur, pas un widget d'encoche autonome. Sans application tierce (comme Vibe Island ou boringNotch), elle n'a aucun contenu à arbitrer. Le guide de démarrage vous signale explicitement si aucune application compatible n'est détectée.

---

## 5. Honnêtement, ce qu'elle n'est pas

### Absence de notarisation Apple

Bouncer est un utilitaire open source gratuit développé de manière indépendante. L'obtention d'un certificat Developer ID et la notarisation automatisée imposent un abonnement payant au programme Apple Developer (99 €/an) que le projet ne souscrit pas. Le binaire est signé localement avec un certificat auto-signé (`Bouncer Local Signing`).

### Message Gatekeeper au premier lancement (hors Homebrew)

Si vous téléchargez l'archive `.zip` directement sans passer par Homebrew, macOS bloque l'exécution initiale avec l'alerte suivante :
> *« macOS n'a pas pu vérifier que Bouncer ne contient pas de logiciel malveillant. »*

L'application n'est ni corrompue ni endommagée : Gatekeeper signale simplement l'absence d'un compte développeur Apple payant.

Pour autoriser l'ouverture (une seule fois) :
1. Double-cliquez sur `Bouncer` dans votre dossier `/Applications` et laissez macOS afficher le refus.
2. Ouvrez **Réglages Système** > **Confidentialité et sécurité**.
3. Faites défiler la page jusqu'à la section Sécurité où apparaît la mention de Bouncer.
4. Cliquez sur **Ouvrir quand même** et confirmez avec votre mot de passe administrateur.

Les ouvertures suivantes s'effectueront directement sans nouvel avertissement.

### Périmètre exclu

- **Aucune API privée instable** : Bouncer n'utilise pas `CGSSetWindowAlpha` ni d'injections WindowServer non documentées qui risqueraient de casser à chaque mise à jour mineure de macOS.
- **Pas de split-screen** : Bouncer ne dessine pas deux applications côte à côte dans la même encoche et ne tente pas de capturer leurs flux visuels.
- **Pas de distribution Mac App Store** : le bac à sable (App Sandbox) obligatoire sur l'App Store interdit l'accès à l'API Accessibilité, rendant impossible le fonctionnement de l'application sur cette plateforme.

---

## Documentation interne et archives

- [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) : analyse technique de Gatekeeper, quarantaine Homebrew et signatures.
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) : mesures de consommation CPU, coût du scan `CGWindowList` et optimisations.
- [`docs/archive/`](docs/archive/) : scripts initiaux de validation technique (`Spike.swift`, `AXProbe.swift`), résultats de mesures d'accessibilité (`SPIKE_RESULTS.md`) et documents d'architecture d'origine (`PRD.md`, `TECH_SPEC.md`, `ROADMAP.md`).
