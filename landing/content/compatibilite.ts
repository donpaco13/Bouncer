/**
 * La matrice de compatibilité, telle que la page la lit.
 *
 * Les FAITS — nom, version, bundleID, voie de bascule, nature de la preuve —
 * vivent dans `compatibilite.json`, qui dérive de `docs/COMPATIBILITE.md`. Ce
 * document-là fait autorité : une correction se fait dans le .md d'abord, et
 * se reporte dans le JSON ensuite. Rien de tout ça ne s'écrit dans le JSX, et
 * rien ne se duplique dans les dictionnaires : deux listes de la même chose
 * finissent toujours par diverger, et ce dépôt en a déjà fait les frais (deux
 * largeurs différentes pour le même boîtier caméra, écrites par deux agents).
 *
 * Ce qui est du TEXTE — le libellé de la voie et la note qui l'explique — vit
 * dans `messages/*.json`, sous la clé `cle`, parce que ça se traduit.
 */
import matrice from "./compatibilite.json";
import type messages from "@/messages/fr.json";

export type Bascule = "rapide" | "relance";
export type Preuve = "mesure" | "predit";

/* La clé qui relie une ligne du JSON à sa note traduite. Elle est tirée du
   dictionnaire français, la langue de référence : une clé inventée dans le JSON
   ne compile pas côté JSX, et `messages/parite.ts` garantit que l'anglais la
   couvre. C'est le seul point de contact entre les deux fichiers, donc le seul
   endroit où ils pourraient diverger. */
export type CleApp = keyof (typeof messages)["compatibilite"]["lignes"];

export type LigneCompatibilite = {
  cle: CleApp;
  app: string;
  version: string;
  bundleID: string;
  bascule: Bascule;
  preuve: Preuve;
};

export const COMPATIBILITE = matrice.apps as readonly LigneCompatibilite[];
