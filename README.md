# Bouncer

Sur un MacBook à encoche, deux apps d'encoche ouvertes en même temps dessinent au même
endroit et se superposent. macOS ne coordonne rien : il n'existe aucune notion d'« app
d'encoche active », donc la seule sortie est de quitter l'une pour utiliser l'autre.

Bouncer régit la visibilité de ces apps : il masque et réaffiche celles qui se
disputent l'encoche, pour qu'une seule y soit visible à la fois. Le contrôle se fait
depuis la barre des menus, par un swipe deux doigts sur l'encoche, ou par deux flèches
qui apparaissent au survol.

Les apps concernées : Vibe Island, boringNotch, Alcove, Notchy, et toutes celles qui
dessinent leur propre pilule sous le hardware notch.

## Ce que ça fait vraiment, aujourd'hui

**Bouncer régit l'app d'encoche que vous avez.** Il ne fait pas encore basculer
entre deux apps, parce que ça n'a jamais pu être démontré : sur les quatre apps
testées, une seule se laisse régir. Faute d'un second candidat, le cycle « app 1 → app
2 → app 1 » est écrit et fonctionnel dans le code, mais jamais vérifié en conditions
réelles.

**Toutes les apps d'encoche ne sont pas régissables**, et ça ne dépend pas de Bouncer.
Autant le savoir avant d'installer.

## Pourquoi certaines apps résistent

Une app d'encoche est régissable si elle laisse ses fenêtres dans le Space de
l'utilisateur. Elle ne l'est pas si elle les épingle dans un Space privé qu'elle crée
elle-même auprès du WindowServer. Ces fenêtres sortent alors du circuit standard de
macOS : l'ordre de masquage (`kAXHiddenAttribute`) est accepté, il ne renvoie aucune
erreur, et il ne change rien à l'écran.

Le critère n'est pas une opinion, il se lit dans le binaire. La ligne de partage est le
**pattern d'écriture de Space** : `CGSSpaceCreate` + `CGSAddWindowsToSpaces` +
`CGSShowSpaces`. Une app qui ne lie que des appels CGS de lecture (interroger les Spaces
existants) reste dans le circuit standard et répond au masquage. Une app qui lie le
pattern d'écriture complet crée son propre Space et s'y épingle : rien ne la déloge sans
API privée.

Vérifier une app vous-même :

```bash
nm -u "/Applications/VotreApp.app/Contents/MacOS/VotreApp" | grep -i CGS
```

Si `CGSSpaceCreate` et `CGSAddWindowsToSpaces` sortent tous les deux, l'app est
vraisemblablement non régissable.

## Compatibilité des apps d'encoche

| Application | Version testée | Régissable | Preuve |
|---|---|:---:|---|
| **Vibe Island** | 1.0.48 | Oui | Mesuré en direct : hide 31,7 ms / show 5,1 ms, confirmé par recomptage `CGWindowList`. Le binaire ne lie que des appels CGS de lecture. |
| **boringNotch** | 2.7.3 | Non | Mesuré en direct : le masquage ne change rien au nombre de fenêtres. Le binaire lie le pattern d'écriture complet, confirmé par lecture de son code source. |
| **Alcove** | 1.7.7 | Non — **prédit**, non confirmé en direct | L'app est restée bloquée à son lancement sur la machine de test (figée à `_dyld_start`), aucune fenêtre à masquer. Le binaire lie le même pattern d'écriture que boringNotch, symbole pour symbole. |
| **Notchy** | 1.0.135 | Non — **prédit**, non confirmé en direct | L'app se lance mais n'affiche aucune fenêtre sans contenu contextuel actif (musique, appel, AirPods, calendrier), donc rien à masquer pendant le test. Le binaire lie le même pattern d'écriture, plus `CGSSetWindowAlpha`. |

**Prédit** veut dire ce que ça dit : Alcove et Notchy n'ont pas été testées de bout en
bout. Leur verdict repose sur l'analyse statique du binaire, pas sur le recomptage
`CGWindowList` avant/après masquage qui a tranché pour les deux autres. Le signal est
net et identique à celui de boringNotch, mais ce n'est pas la même preuve.

Le détail complet des mesures, des commandes et des impasses est dans
[`SPIKE_RESULTS.md`](SPIKE_RESULTS.md), section « Compatibilité des applications
d'encoche ».

Une app d'encoche testée qui manque au tableau ? Le résultat de la commande `nm -u`
ci-dessus suffit à l'ajouter.

## Comportement face à une app non régissable

Bouncer détecte toutes les fenêtres de la zone d'encoche, teste chaque app une
fois à sa découverte, puis marque celles qui ne répondent pas comme « Non supportée ».
Elles restent listées dans le menu mais sortent du cycle de switch, et ne sont plus
jamais retestées : pas de clignotement en boucle, pas de fenêtre laissée masquée après
le test.

Le seul juge de vérité pour un masquage est le recomptage `CGWindowList` sur le pid
ciblé. Ni le code retour de l'API Accessibility ni la relecture de l'attribut ne
signalent l'échec sur boringNotch : ils rapportent un succès qui n'a pas eu lieu.

## Installation

Pas encore de DMG signé ni de release. Compilation depuis les sources :

```bash
git clone <ce-dépôt>
cd "Island Switch"
./build.sh
```

`build.sh` compile en release, fabrique le bundle `.app`, le signe avec un certificat
local persistant et relance l'app. Le certificat est créé au premier run et réutilisé
ensuite : sans lui, la signature ad-hoc change à chaque build et macOS redemande
l'autorisation Accessibilité à chaque itération.

Prérequis : macOS 14 (Sonoma) ou plus récent, un MacBook à encoche, et les Command Line
Tools Xcode (Swift 5.9+).

### Autorisation Accessibilité

Bouncer a besoin de l'autorisation Accessibilité pour masquer les fenêtres
tierces. L'app la demande au premier lancement ; le menu propose aussi « Autoriser dans
les Réglages… » qui ouvre directement le bon volet.

L'autorisation se donne **par binaire**, pas par app ni par processus parent. Si vous
recompilez ailleurs ou lancez le binaire depuis un terminal, il faut réautoriser.

### Vérifier sans interface

```bash
"Bouncer.app/Contents/MacOS/Bouncer" --self-test
```

Imprime l'état de l'autorisation, la géométrie de l'encoche détectée, et la liste des
apps trouvées avec leur statut de régissabilité. Un seul passage, pas de boucle.

## Réglages

Le menu de la barre des menus ouvre une fenêtre de préférences (⌘,), en trois onglets.

- **Général** : lancement à l'ouverture de session, et période à laquelle Bouncer
  resonde les apps de l'encoche. 2 s par défaut ; ce scan coûte 2,7 ms à chaque tour,
  d'où le choix jusqu'à 30 s pour une machine qu'on veut laisser tranquille.
- **Geste** : ce qui fait tourner le cycle, le swipe, les flèches ou les deux. Puis,
  pour les flèches, la distance à laquelle elles s'allument (72 pt) et la largeur des
  bandes où elles se logent de part et d'autre du boîtier caméra (44 pt).
- **Applications** : décocher une app la retire du cycle sans la retirer du menu. Le
  swipe l'ignore, un clic dans le menu la désigne toujours.

Il n'y a pas de réglage de sensibilité du swipe, et c'est voulu. Le seuil a été mesuré
comme n'étant pas un levier : 6, 8, 12 et 20 points donnent le même résultat, parce que
ce qui découpe les gestes est la phase du geste physique et non la distance parcourue.
Un curseur donnerait l'impression de régler une valeur qui ne change rien.

## Fonctionnement

- **Détection** : `CGWindowListCopyWindowInfo` filtré sur les fenêtres qui intersectent
  la zone d'encoche, elle-même dérivée de `NSScreen.safeAreaInsets.top` (aucune
  coordonnée en dur). Les processus système sont écartés par bundleID, jamais par nom
  d'affichage, qui suit la langue du système.
- **Régie** : `kAXHiddenAttribute` au niveau application, vérifié par recomptage.
- **Overlay** : un `NSPanel` non activant, transparent, qui porte les flèches et n'est
  ordonné à l'écran que pendant le survol de l'encoche. Hors survol, aucune fenêtre
  de Bouncer ne recouvre la zone.
- **Swipe** : monitor global sur `.scrollWheel`, attaché seulement quand le curseur est
  dans la zone d'encoche et que le swipe est activé. Hors de là, Bouncer n'écoute aucun
  défilement. La décision « ce geste est-il un swipe » raisonne en gestes physiques
  (phases `NSEvent`) et non en distance cumulée : un geste donne une bascule, et la
  traîne d'inertie qui le suit n'en donne aucune. Le monitor doit être global : dès
  qu'une app d'encoche déploie son panneau, sa fenêtre consomme le scroll avant nous.

L'encoche n'est pas forcément sur `NSScreen.main`. Sur la machine de test, l'écran
principal est un moniteur externe sans encoche et le MacBook est l'écran secondaire.

## État du projet

Milestones 0 à 2 terminés : spike de faisabilité, app menu bar avec détection et régie,
overlay avec flèches et swipe. Milestone 3 entamé : l'onboarding et les préférences sont
faits ; restent la signature Developer ID, la notarisation et le DMG.

Voir [`ROADMAP.md`](ROADMAP.md) pour le découpage, [`TECH_SPEC.md`](TECH_SPEC.md) pour
l'architecture, [`PRD.md`](PRD.md) pour le cadrage produit.

## Hors périmètre

Bouncer ne réimplémente aucune fonctionnalité des apps tierces, n'affiche pas deux
apps côte à côte dans l'encoche, et ne capture pas leur contenu pour le redessiner. Il
décide seulement qui est visible.

Les apps qui épinglent leurs fenêtres dans un Space privé resteront hors périmètre tant
qu'il n'existe pas de moyen public de les régir. Le seul repli identifié passe par
`CGSSetWindowAlpha`, une API privée non documentée : elle expose à un rejet de
notarisation et à une rupture sans préavis à la prochaine mise à jour de macOS. Ce
n'est pas un compromis acceptable pour une app distribuée.

Pas de distribution Mac App Store : le sandboxing y interdit l'API Accessibility dont
dépend tout le produit.
