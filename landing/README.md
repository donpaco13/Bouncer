# Landing Bouncer

Page de présentation de Bouncer. Next.js 15 (App Router), `next-intl` pour les
deux langues, CSS classique, exportée en site statique. Aucun serveur à faire
tourner en production.

```
npm install
npm run dev        # http://localhost:3000/en/ (et /fr/)
npm run build      # écrit out/, servable tel quel
npm run typecheck
```

## Ce que montre la page

La page reprend la maquette validée « direction 1 v2, l'écran est la page »
(`propositions/direction-1-v2.html` dans la branche de design). Le haut de la
fenêtre du navigateur est le haut de l'écran du Mac.

1. **Le héros** (`components/bureau.tsx`). La barre des menus sert de
   navigation au site. L'encoche pend au milieu et elle marche : clic,
   balayage à deux doigts sur le trackpad, flèches au survol, `⌃⌥⌘B`, et le
   menu de Bouncer en haut à droite, avec ● ○ ◐ et l'interrupteur. Trois
   apps tournent : Vibe Island et NotchNook basculent tout de suite,
   boringNotch passe par une relance et l'app en place reste affichée tant
   que la nouvelle n'est pas arrivée.
2. **Pourquoi** : le conflit entre deux apps dessiné en éclaté, puis la même
   encoche avec Bouncer.
3. **Quatre façons de changer d'app**, chacune dessinée sur la même encoche.
4. **La compatibilité**, remontée parce que le héros y renvoie : 7 apps
   mesurées, 3 prédites, lues dans `content/compatibilite.json`, et pour
   chacune ce qu'elle devient quand elle est cachée.
5. **La fiabilité**, sur fond sombre : ≈ 50 ms, ≈ 1 s, et la frise
   « allumer avant d'éteindre ». Le détail technique reste dans
   `docs/COMPATIBILITE.md`.
6. **L'installation** : le .zip et Homebrew à poids égal, les prérequis, et
   Gatekeeper replié.

## Les deux langues

Le texte vit dans `messages/fr.json` et `messages/en.json`. Le **français est
la langue de référence** : c'est sa forme qui définit les clés, via
l'augmentation de `AppConfig` dans `global.d.ts`.

Deux filets, tous les deux au compilateur :

- une clé qui n'existe pas dans `fr.json` ne s'écrit pas dans le code ;
- `messages/parite.ts` refuse de compiler si une traduction oublie ou renomme
  une clé.

Le français porte ses espaces fines insécables avant `? ! ; :` et dans les
guillemets. « macOS 14 » est insécable dans les deux langues.

Le bureau du héros est un composant client, mais il reçoit des chaînes déjà
résolues, annonces du lecteur d'écran comprises : aucun dictionnaire ne part au
navigateur.

### Ce qui ne se traduit pas vit dans `content/`

- `liens.ts` : les URL, la commande Homebrew, et **`SITE`, l'adresse publique
  du site**. Toutes les URL absolues en dérivent.
- `compatibilite.json`, lu par `compatibilite.ts` : la matrice et la date de la
  campagne. **Il dérive de `docs/COMPATIBILITE.md`, et c'est ce document-là qui
  fait autorité.** Une correction se fait dans le `.md` d'abord, puis dans le
  JSON. Le JSON ne porte que des faits (nom, version, bundleID, voie, preuve) ;
  la note courte de chaque ligne est du texte et vit dans les dictionnaires,
  sous la clé `cle`.
- `demo.ts` : les trois apps du héros. Le nom et la voie viennent de la
  matrice, et `appDemo` fait échouer le build si on y met une app seulement
  prédite.

### Ce que l'export statique impose

`output: "export"` veut dire pas de proxy, donc pas de négociation de langue au
serveur.

1. **Le préfixe de langue est obligatoire** (`localePrefix: "always"`).
   L'anglais est à `/en/`, le français à `/fr/`.
2. **`/` est une page d'aiguillage** (`app/(racine)/`) : un rafraîchissement
   immédiat vers `/en/`.
3. **Chaque langue doit être pré-rendue**, d'où `generateStaticParams` et
   `setRequestLocale` dans `app/(site)/[locale]/`.

Le lien de langue est une ancre nue, pas le `Link` de `next-intl`, qui
réclamerait un `NextIntlClientProvider` et un dictionnaire côté navigateur.

## Ajouter une langue

1. Ajouter son code à `locales` et son nom à `NOMS_LANGUES`, dans
   `i18n/routing.ts`, et sa locale Open Graph dans `content/seo.ts`.
2. Copier `messages/fr.json`, traduire les valeurs.
3. Vérifier la nouvelle langue dans `messages/parite.ts`, sur le modèle de
   l'anglais.

Le lien de langue suppose deux langues : au-delà, il faut lui donner une liste.

## SEO

- **Titre et description** dans `messages/*.json`, sous `meta`. Ils portent
  les mots que les gens tapent : « notch app manager », « switch notch apps ».
- **URL absolues** : canonical, hreflang (en, fr, x-default), og:url, image de
  partage, sitemap et JSON-LD passent tous par `absolue()` dans
  `content/seo.ts`, qui part de `SITE`. Aucun domaine n'est encore choisi :
  `SITE` vaut l'adresse GitHub Pages du dépôt. **Le jour où le domaine est
  choisi, c'est la seule ligne à changer.** Si la page est servie dans un
  sous-dossier (GitHub Pages d'un dépôt), il faudra aussi un `basePath` dans
  `next.config.ts`, sinon `/_next/` ne se charge pas.
- **Image de partage** (`app/og/[fichier]/route.tsx`) : `/og/en.png` et
  `/og/fr.png`, 1200 × 630, dessinées au build depuis le titre traduit. C'est
  une route plutôt que la convention `opengraph-image` de Next, parce qu'en
  export celle-ci écrit un fichier sans extension, qu'un hébergeur statique
  sert alors en `application/octet-stream`. La carte Twitter est en
  `summary_large_image`.
- **JSON-LD** `SoftwareApplication` dans `app/(site)/[locale]/page.tsx` :
  macOS 14, prix 0, catégorie Utilities, licence MIT.
- **`robots.txt` et `sitemap.xml`** : `app/robots.ts` et `app/sitemap.ts`.

## Où est la mise en forme

Tout est dans `app/globals.css`, en CSS classique : c'est la feuille de la
maquette, reprise telle quelle pour que le rendu ne dérive pas. Les classes
sont nommées par section (`.menubar`, `.stage`, `.scene`, `.tl`, `.tbl`,
`.ways2`…).

**Toute la géométrie de l'encoche dérive de `--nw` et `--nh`** : la zone
réservée dans la barre des menus, la largeur dépliée des pastilles (`--w`, en
multiples de `--nw`) et la position des flèches (`--cw`, la largeur de l'app en
place). Les scènes de la page redéfinissent ces deux variables à leur échelle
et tout suit. Le texte d'une pastille doit tenir dans l'aile droite, de part et
d'autre de l'encoche, sinon l'encoche le recouvre.

Les dessins (pastilles, logo, pomme) sont des SVG dans `components/signes.tsx`.
Aucune image, aucune police, aucun appel réseau.

## Les intentions à ne pas casser

- **L'encoche du héros est le produit.** On voit Bouncer marcher avant
  d'avoir lu une ligne, avec les vraies pièces de l'app : flèches au survol,
  menu ● ○ ◐, interrupteur, raccourci.
- **Rien ne bouge tout seul dans la démo.** Chaque changement d'état vient
  d'un clic, d'une touche ou d'un balayage. Ce qui s'anime sans geste montre
  un geste à faire : les deux doigts de l'infobulle, et les gestes dessinés
  dans les cartes « quatre façons ».
- **L'interrupteur porte le problème ET sa solution.** Bouncer éteint, les
  trois pastilles dessinent au même endroit, cerclées de rouge.
- **La voie relance montre la règle « on avant off ».** Le menu passe en ◐,
  un liseré jaune entoure l'app qui attend, et elle ne part qu'une fois la
  nouvelle à l'écran.
- **`prefers-reduced-motion`** coupe toutes les transitions et animations ;
  la démo reste entièrement jouable.
- **Mobile** : à 390 px, aucune zone cliquable sous 44 × 44. Les commandes de
  la barre des menus gardent leur dessin de 32 px et prolongent leur zone de
  toucher dessous.
- **La colonne « Preuve » du tableau ne se gomme pas.** Mesuré et prédit ne se
  mélangent jamais.
- **Les deux points d'honnêteté restent tels quels, dans les deux langues** :
  Gatekeeper (l'app n'est pas notarisée, macOS dira « n'a pas pu vérifier » /
  « cannot verify », jamais « endommagée » / « is damaged », et le passage par
  Réglages Système reste écrit) et la distinction mesuré / prédit. Nulle part
  on n'écrit que l'app est « signée ». Le volet Gatekeeper dit aussi que le
  cask Homebrew retire l'attribut de quarantaine lui-même.

## Vérifier

```
npm run build
cd out && python3 -m http.server 4802
```

Puis ouvrir `http://localhost:4802/en/` et `/fr/` à 1440 et 390 px de large.
Les captures de l'intégration (avant, maquette, après) sont dans
`propositions/captures/integration/`.
