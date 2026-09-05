/* Les URL ne se traduisent pas : elles vivent ici, pas dans les dictionnaires,
   pour qu'une correction de lien n'ait pas à être répétée dans chaque langue. */
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

/** La commande de vérification, identique dans toutes les langues. Elle imprime
    ce que Bouncer a trouvé sous l'encoche de la machine où on la tape. */
export const COMMANDE_VERIF =
  '"/Applications/Bouncer.app/Contents/MacOS/Bouncer" --self-test';
