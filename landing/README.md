# Landing Bouncer

Page de présentation de Bouncer. Next.js 15 (App Router) + Tailwind CSS 4,
exportée en site statique — aucun serveur à faire tourner en production.

```
npm install
npm run dev        # http://localhost:3000/fr/ (et /en/)
npm run build      # écrit out/, servable tel quel
npm run typecheck
```

## Pourquoi Next plutôt qu'un fichier HTML

La page a commencé en un seul fichier (`docs/landing/index.html`, dans
l'historique git jusqu'au portage), et il a fallu la traduire.

Dupliquer une page statique, c'est garantir qu'une correction ne sera faite que
d'un côté. Ici le balisage est écrit une fois, et les deux langues rendent le
même arbre : le seul écart entre `out/fr/index.html` et `out/en/index.html`
après un build tient aux scripts d'hydratation de Next, pas au contenu.

## Les deux langues

`next-intl` porte les dictionnaires ; le texte vit dans `messages/fr.json` et
`messages/en.json`. Le **français est la langue de référence** : c'est sa forme
qui définit les clés, via l'augmentation de `AppConfig` dans `global.d.ts`.

Deux filets, tous les deux au compilateur :

- une clé qui n'existe pas dans `fr.json` ne s'écrit pas dans le code ;
- `messages/parite.ts` refuse de compiler si une traduction oublie ou renomme
  une clé. C'est deux lignes, et c'est ce qui empêche les versions de diverger.

Ce qui ne se traduit pas vit dans `content/` : les URL et les deux commandes
(`liens.ts`), et la matrice de compatibilité (`compatibilite.json`, lu par
`compatibilite.ts`). Y dupliquer « 1.0.48 » dans chaque langue, ce serait se
garantir qu'une mise à jour n'en corrigera qu'une.

**`content/compatibilite.json` dérive de `docs/COMPATIBILITE.md`, et c'est ce
document-là qui fait autorité.** Une correction se fait dans le `.md` d'abord,
et se reporte dans le JSON ensuite. Le JSON ne porte que des faits — nom,
version, bundleID, voie de bascule, nature de la preuve ; le libellé de la voie
et la note qui l'explique sont du texte, et vivent dans les dictionnaires sous
la clé `cle`. Ce champ est typé depuis `messages/fr.json` : une clé inventée
dans le JSON ne compile pas.

### Ce que l'export statique impose

`output: "export"` veut dire pas de proxy, donc pas de négociation de langue au
serveur. Trois conséquences, et ce ne sont pas des choix :

1. **Le préfixe de langue est obligatoire** (`localePrefix: "always"`). Le
   français est à `/fr/`, l'anglais à `/en/`.
2. **`/` est une page d'aiguillage** (`app/(racine)/`) : un rafraîchissement
   immédiat vers `/fr/`, en chemin relatif pour que le site marche aussi servi
   depuis un sous-dossier.
3. **Chaque langue doit être pré-rendue**, d'où `generateStaticParams` et
   `setRequestLocale` dans `app/(site)/[locale]/`. Sans eux, le rendu bascule en
   dynamique et le build échoue.

Le sélecteur de langue est une ancre nue, pas le `Link` de `next-intl` : celui-ci
devient un composant client dès qu'on lui passe une langue et réclame alors un
`NextIntlClientProvider`. Aucun dictionnaire ne part au navigateur — les scènes
animées sont des composants client, mais elles reçoivent des chaînes déjà
résolues.

## Ajouter une langue

Trois gestes, et le compilateur surveille le reste :

1. Ajouter son code à `locales` et son nom à `NOMS_LANGUES`, dans
   `i18n/routing.ts`.
2. Copier `messages/fr.json`, traduire les valeurs.
3. Vérifier la nouvelle langue dans `messages/parite.ts`, sur le modèle de
   l'anglais.

Le sélecteur suppose deux langues : au-delà, il faut lui donner une liste.

## Où est la mise en forme

- `app/globals.css` — les jetons de design dans `@theme` (Tailwind en fait des
  utilitaires : `bg-papier`, `py-pas`, `text-titre`…), puis **le mécanisme de
  l'aperçu** en CSS classique. Ce dernier bloc reste groupé volontairement :
  une seule variable, `--lg-encoche`, pilote la largeur du rectangle noir, les
  colonnes de la grille de la pilule, la hauteur de la barre des menus et la
  position des flèches. Éclatée en utilitaires, cette dépendance disparaît et
  la géométrie diverge.
- `components/mise-en-page.ts` — les cinq mesures qui tiennent le rythme
  (colonne, bloc de lecture, titre, chapô, sous-titre).
- Tout le reste est en utilitaires Tailwind dans le JSX.

## Les intentions à ne pas casser

Elles sont commentées à l'endroit où elles vivent, mais en résumé :

- **L'aperçu du héros est le produit, pas une illustration.** On voit Bouncer
  marcher avant d'avoir lu une ligne : une fenêtre macOS avec l'encoche vivante
  dedans, trois apps dans le Dock, et quatre façons d'en changer — le Dock, les
  flèches du boîtier caméra, les flèches du clavier, et le vrai raccourci
  `⌃⌥⌘B`, branché sur la page. C'est la promesse à ne pas perdre.
- **Rien ne bouge tout seul.** Pas de minuterie, pas de scène qui se joue devant
  un visiteur passif : chaque changement d'état vient d'un clic, d'une touche ou
  d'un survol. Une animation qui se déclenche seule ne montre pas le produit,
  elle le raconte.
- **L'interrupteur porte le problème ET sa solution.** Bouncer débranché, les
  trois pilules dessinent au même endroit et les valeurs se chevauchent. C'est
  ce que macOS affiche vraiment, et c'est le visiteur qui bascule de l'un à
  l'autre. Sans lui, la section « macOS ne coordonne rien » n'a rien à montrer.
- **`prefers-reduced-motion` ne démonte rien**, parce qu'il n'y a rien à
  démonter : on coupe les fondus et le décollement des tuiles, et l'aperçu reste
  entièrement jouable, à la souris comme au clavier.
- **Les pilules de démo ne nomment aucune app tierce.** La matrice les nomme,
  elle, parce qu'elle rend compte de mesures. Une démo jouable, non.
- **La colonne « Preuve » du tableau ne se gomme pas.** Mesuré et prédit ne se
  mélangent jamais : c'est ce qui rend la section crédible, et une matrice qui
  efface la nuance redevient une promesse invérifiable. Même chose pour la voie
  « Pas encore vue » — trois apps ne sont pas détectées aujourd'hui à cause du
  filtre de largeur à 80 %, c'est mesuré, et la page le dit.
- **Les deux points d'honnêteté restent tels quels, dans les deux langues** :
  Gatekeeper (l'app n'est pas notarisée, macOS dira « n'a pas pu vérifier » /
  « cannot verify », jamais « endommagée » / « is damaged », et le passage par
  Réglages Système reste ouvert) et la distinction mesuré / prédit du tableau.
  Nulle part on n'écrit que l'app est « signée » : le certificat est local et ne
  vaut rien sur une autre machine.
