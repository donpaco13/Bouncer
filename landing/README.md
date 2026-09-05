# Landing Bouncer

Page de présentation de Bouncer. Next.js 15 (App Router) + Tailwind CSS 4,
exportée en site statique — aucun serveur à faire tourner en production.

```
npm install
npm run dev        # http://localhost:3000
npm run build      # écrit out/, servable tel quel
npm run typecheck
```

## Pourquoi Next plutôt qu'un fichier HTML

La page existait en un seul fichier (`docs/landing/index.html`, dans l'historique
git jusqu'au portage). Elle était bonne, et le portage la reproduit au pixel :
même arbre DOM, mêmes boîtes, mêmes valeurs.

Ce qui a changé, c'est la **version anglaise à venir**. Dupliquer une page
statique, c'est garantir qu'une correction ne sera faite que d'un côté. Ici le
balisage est écrit une fois et le texte vit dans un dictionnaire typé.

## Ajouter une langue

Trois gestes, et le compilateur surveille le reste :

1. `content/en.tsx` — copier `fr.tsx`, traduire les valeurs. Le type
   `Dictionary` refuse une clé manquante ou renommée : c'est ce qui empêche les
   deux versions de diverger.
2. `app/(en)/layout.tsx` et `app/(en)/page.tsx` — copier ceux de `(fr)`, changer
   `lang="en"`, le dictionnaire importé, et le chemin de la route.
3. Ajouter `"en"` à `LOCALES` dans `content/dictionary.ts`.

Le français est servi à la racine (`/`), les autres langues sous leur préfixe.
Chaque langue est un groupe de routes avec sa propre racine, donc son propre
attribut `lang` — indispensable aux lecteurs d'écran.

Ce qui ne se traduit pas vit dans `content/liens.ts` : URL, commande Homebrew,
favicon.

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
- **Les deux points d'honnêteté restent tels quels** : Gatekeeper (l'app n'est
  pas notarisée, macOS dira « n'a pas pu vérifier », pas « endommagée ») et la
  colonne mesuré / prédit du tableau.
