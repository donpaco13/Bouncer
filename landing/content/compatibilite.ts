/* Ce qui ne se traduit pas : le nom d'une app, le numéro de version qu'on a
   testé, et le verdict qui décide de la couleur. Le libellé du verdict et la
   note, eux, sont du texte — ils vivent dans les dictionnaires, sous la même
   clé. Dupliquer « 1.0.48 » dans chaque langue, c'est se garantir qu'une mise à
   jour n'en corrigera qu'une. */
export const COMPATIBILITE = [
  { cle: "vibeIsland", app: "Vibe Island", version: "1.0.48", verdict: "oui" },
  { cle: "boringNotch", app: "boringNotch", version: "2.7.3", verdict: "non" },
  { cle: "alcove", app: "Alcove", version: "1.7.7", verdict: "non" },
  { cle: "notchy", app: "Notchy", version: "1.0.135", verdict: "non" },
] as const;
