/**
 * LES APPS QUE L'ENCOCHE DU HÉROS MET EN SCÈNE.
 *
 * Une seule constante à changer, `APPS_APERCU`, et l'encoche, le menu de
 * Bouncer et le lecteur d'écran suivent. La question « quelle app mettre en
 * avant » se rejoue à chaque nouvelle mesure, et elle ne doit jamais demander
 * de retoucher du JSX.
 *
 * LA RÈGLE QUI NE SE NÉGOCIE PAS : n'inscrire ici qu'une app MESURÉE dans
 * `compatibilite.json`. Le nom et la voie de bascule viennent de là, pas d'ici,
 * et `appDemo` fait échouer le build si la ligne est seulement prédite. Mettre
 * en vitrine une app que Bouncer n'a jamais basculée, ce serait promettre ce
 * que le produit n'a pas prouvé.
 *
 * Le trio couvre les deux voies du moteur : Vibe Island et NotchNook partent
 * par masquage, boringNotch par relance parce qu'elle épingle sa fenêtre dans
 * un Space privé. Une seule encoche montre tout le moteur, « on avant off »
 * compris.
 */
import type messages from "@/messages/fr.json";
import { COMPATIBILITE, type CleApp } from "./compatibilite";

/** La clé du contenu affiché dans la pastille. Tirée du dictionnaire français,
    la langue de référence : une clé inventée ici ne compile pas. */
export type CleContenu = keyof (typeof messages)["demo"]["contenus"];

/** Le signe dessiné à gauche dans la pastille, en SVG dans `signes.tsx` :
    aucune requête réseau, aucun logo tiers à s'approprier. */
export type Signe = "pastilles" | "onde" | "tiroir";

export type AppApercu = {
  cle: CleApp;
  contenu: CleContenu;
  signe: Signe;
  /** Largeur de la pastille dépliée, en multiples de la largeur de l'encoche.
      Chaque app a la sienne : c'est ce qui rend la bascule visible. */
  largeur: number;
};

export const APPS_APERCU = [
  { cle: "vibeIsland", contenu: "agents", signe: "pastilles", largeur: 2.05 },
  { cle: "boringNotch", contenu: "musique", signe: "onde", largeur: 1.78 },
  { cle: "notchNook", contenu: "fichiers", signe: "tiroir", largeur: 1.92 },
] as const satisfies readonly [AppApercu, AppApercu, ...AppApercu[]];

/** La ligne de la matrice qui porte une app de la démo. Lève au build si
    l'app n'est pas mesurée. */
export function appDemo(cle: CleApp) {
  const ligne = COMPATIBILITE.find((l) => l.cle === cle);
  if (!ligne || ligne.preuve !== "mesure") {
    throw new Error(`demo.ts : ${cle} n'est pas une app mesurée`);
  }
  return ligne;
}
