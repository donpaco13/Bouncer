/* Les URL ne se traduisent pas : elles vivent ici, pas dans les dictionnaires,
   pour qu'une correction de lien n'ait pas à être répétée dans chaque langue. */
/** L'adresse publique du site, sans barre finale. Toutes les URL absolues en
    dérivent : canonical, hreflang, og:url, image de partage, sitemap, robots.
    AUCUN DOMAINE N'EST ENCORE CHOISI : c'est l'adresse GitHub Pages du dépôt,
    et c'est la seule ligne à changer le jour où la landing a son domaine. */
export const SITE = "https://donpaco13.github.io/Bouncer";

export const LIENS = {
  depot: "https://github.com/donpaco13/Bouncer",
  versions: "https://github.com/donpaco13/Bouncer/releases",
  matrice:
    "https://github.com/donpaco13/Bouncer/blob/main/docs/COMPATIBILITE.md",
} as const;

/** La ligne d'installation est identique dans toutes les langues. */
export const COMMANDE_BREW = "brew install --cask donpaco13/tap/bouncer";

/** Le quatrième emploi de la même forme : le rectangle noir de l'encoche,
    dessiné en SVG, sert de favicon. Aucune requête réseau. */
export const FAVICON =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cpath d='M6 0h20v9a5 5 0 0 1-5 5H11a5 5 0 0 1-5-5z' fill='%23000'/%3E%3C/svg%3E";
