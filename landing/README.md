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

La page existait en un seul fichier (`docs/landing/index.html`, dans l'historique
git jusqu'au portage). Elle était bonne, et le portage la reproduit au pixel :
même arbre DOM, mêmes boîtes, mêmes valeurs.

Ce qui a changé, c'est **l'anglais**. Dupliquer une page statique, c'est garantir
qu'une correction ne sera faite que d'un côté. Ici le balisage est écrit une
fois, et les deux langues rendent le même arbre — 209 éléments, vérifiés
identiques d'une langue à l'autre après chaque build.

## Les deux langues

`next-intl` porte les dictionnaires ; le texte vit dans `messages/fr.json` et
`messages/en.json`. Le **français est la langue de référence** : c'est sa forme
qui définit les clés, via l'augmentation de `AppConfig` dans `global.d.ts`.

Deux filets, tous les deux au compilateur :

- une clé qui n'existe pas dans `fr.json` ne s'écrit pas dans le code ;
- `messages/parite.ts` refuse de compiler si une traduction oublie ou renomme
  une clé. C'est deux lignes, et c'est ce qui empêche les versions de diverger.

Ce qui ne se traduit pas vit dans `content/` : les URL et la commande Homebrew
(`liens.ts`), le nom et la version des apps testées (`compatibilite.ts`). Y
dupliquer « 1.0.48 » dans chaque langue, ce serait se garantir qu'une mise à
jour n'en corrigera qu'une.

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
  l'encoche** en CSS classique. Ce dernier bloc reste groupé volontairement :
  une seule variable, `--lg-encoche`, pilote la largeur du rectangle noir, les
  colonnes de la grille du panneau et la position des flèches. Éclatée en
  utilitaires, cette dépendance disparaît et la géométrie diverge d'une scène à
  l'autre.
- `components/mise-en-page.ts` — les quatre mesures qui tiennent le rythme
  (colonne, bloc de lecture, titre, chapô).
- Tout le reste est en utilitaires Tailwind dans le JSX.

## Les intentions à ne pas casser

Elles sont commentées à l'endroit où elles vivent, mais en résumé :

- **Le héros superpose littéralement les deux panneaux.** Ils occupent le même
  rectangle, « 4 agents » et « 2:41 » s'écrivent l'un sur l'autre. Ça se lit
  comme un bug d'affichage — c'est le problème que macOS laisse à l'utilisateur.
- **La démo du geste est pilotée par le défilement, jamais par un timer.** Les
  deux doigts traversent l'encoche à la vitesse du scroll. Le mouvement répond à
  une action au lieu de se déclencher tout seul.
- **`prefers-reduced-motion` démonte le mécanisme au lieu de le figer** : la
  piste retombe à sa hauteur naturelle, le collant redevient statique, un seul
  panneau reste. Les flèches restent pilotables au clic et au clavier dans les
  deux régimes.
- **Les panneaux de démo ne nomment aucune app tierce.** Le tableau de
  régissabilité écrit trois écrans plus bas que le cycle entre deux apps n'a
  jamais pu être vérifié faute d'un second candidat : nommer une app dans une
  démo de bascule le contredirait.
- **Les deux points d'honnêteté restent tels quels, dans les deux langues** :
  Gatekeeper (l'app n'est pas notarisée, macOS dira « n'a pas pu vérifier » /
  « cannot verify », jamais « endommagée » / « is damaged », et le passage par
  Réglages Système reste ouvert) et la colonne mesuré / prédit du tableau. Nulle
  part on n'écrit que l'app est « signée » : le certificat est local et ne vaut
  rien sur une autre machine.
