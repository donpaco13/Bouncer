# Bouncer — bascule entre apps de notch

Design validé le 2026-09-01. Remplace la promesse « masquer/réafficher » par « une seule app
de notch active à la fois », en assumant que toutes les apps ne se laissent pas masquer.

## Pourquoi ce changement

Le produit s'appelait Island Switch et reposait entièrement sur `kAXHiddenAttribute`. Sur les
quatre apps de notch testées, une seule y répond. Les trois autres épinglent leurs fenêtres dans
un Space privé du WindowServer : l'ordre de masquage est accepté, ne renvoie pas d'erreur, et ne
change rien à l'écran. La feature centrale — basculer entre deux apps — n'a donc jamais pu être
démontrée, faute d'un second candidat régissable.

Le masquage n'était pas la fin, c'était un moyen. L'objectif réel est qu'une seule app occupe le
notch. Quitter et relancer atteint cet objectif sur 100 % des apps, avec de l'API publique.

## Le nom

**Bouncer**. Le nom dit le mécanisme : sortir une app, en faire entrer une, une seule à la fois.
Turnstile a été écarté pour collision avec Cloudflare Turnstile. Aucune app macOS établie ne
porte le nom Bouncer.

Bundle id : `io.github.donpaco13.bouncer`. L'ancien `fr.yeita.islandswitch` plaçait un projet
personnel sous le reverse-DNS de l'employeur du propriétaire, ce qui suggérait qu'il lui
appartenait. Le renommage coûte une réautorisation Accessibilité — TCC lie l'autorisation au
bundle id. C'est la dernière : le nouveau bundle id est définitif.

## Architecture

### Deux méthodes, choisies par app

On n'abandonne pas le masquage, on l'ajoute à une seconde voie. Vibe Island se masque en 31,7 ms
et se réaffiche en 5,1 ms : la tuer et la relancer serait absurde. Bouncer choisit selon le
verdict de régissabilité qu'il mesure déjà :

- **app régissable** → `kAXHiddenAttribute`, instantané, l'app reste chaude et garde son état
- **app résistante** → cycle de vie : lancer la suivante, attendre, tuer la précédente

### La liste ne peut plus venir des process vivants

Une app tuée disparaît de `CGWindowList`. La source de vérité devient les apps **installées sur
le disque**, et l'état de chacune : installée / lancée / active dans le notch. C'est le vrai
changement d'architecture, pas la bascule elle-même.

### Séquence de bascule, pour une app résistante

Ordre validé avec le propriétaire : **on lance B avant de tuer A**, pour que l'utilisateur ne voie
jamais un notch vide. Le prix est un bref chevauchement où les deux apps se superposent — le
problème même que Bouncer résout, mais sous contrôle et pour une seconde.

1. `NSWorkspace.openApplication` sur B
2. sonder `CGWindowListCopyWindowInfo` toutes les 50 ms jusqu'à ce qu'une fenêtre de B apparaisse
   dans la zone du notch
3. `NSRunningApplication.terminate()` sur A

**Timeout obligatoire.** Si B n'apparaît jamais — app cassée, lancement lent, permission
manquante — on ne tue PAS A. L'échec doit laisser l'utilisateur avec l'app qu'il avait, jamais
avec un notch vide et deux apps mortes.

## En parallèle : la PR à boringNotch

boringNotch est open source et contient déjà une fonction `togglePopover()` qui fait le
`orderOut()` qu'il faudrait — elle n'est appelée nulle part. L'exposer par un URL scheme ou une
notification distribuée est une petite PR. Si elle passe, boringNotch bascule dans la voie rapide
et Bouncer gagne son deuxième candidat régissable, ce qui rendrait enfin la bascule
démontrable en conditions réelles.

## Hors périmètre

`CGSSetWindowAlpha` reste écarté : API privée, casse sans préavis à chaque version de macOS.
L'argument de la notarisation ne mord pas aujourd'hui (pas de Developer ID), mais celui de la
fragilité suffit.
