/**
 * LE COUPLE D'APPS QUE L'APERÇU MET EN SCÈNE.
 *
 * Une seule constante à changer — `APPS_APERCU` — et l'aperçu, le pupitre, les
 * libellés des flèches et le lecteur d'écran suivent. C'est volontaire : la
 * question « quelle app mettre en avant » se rejoue à chaque nouvelle mesure,
 * et elle ne doit jamais demander de retoucher du JSX.
 *
 * LA RÈGLE QUI NE SE NÉGOCIE PAS : n'inscrire ici qu'une app que Bouncer régit
 * pour de vrai, c'est-à-dire une ligne de `docs/COMPATIBILITE.md` § 3.1. Les
 * apps les plus connues — NotchNook, Notchy, Mew Notch — dessinent sur 1352 pt,
 * soit 100 % de l'écran ; le filtre de détection s'arrête à 80 % et Bouncer ne
 * les voit pas. Les mettre en vitrine serait promettre ce que le produit ne
 * fait pas.
 *
 * Le couple par défaut n'est pas un pis-aller, c'est le meilleur argument
 * disponible : boringNotch est l'app d'encoche libre la plus installée du lot
 * régi, et le duo couvre à lui seul les DEUX voies de bascule — Vibe Island
 * part en 46 ms par masquage, boringNotch en ~1 s par relance parce qu'elle
 * épingle sa fenêtre dans un Space privé. Une seule scène démontre tout le
 * moteur.
 */
import type messages from "@/messages/fr.json";

/** La clé du contenu affiché dans la pilule. Tirée du dictionnaire français,
    la langue de référence : une clé inventée ici ne compile pas. */
export type CleContenu = keyof (typeof messages)["demo"]["contenus"];

/** Le signe dessiné à gauche dans la pilule. Trois formes, dessinées en SVG
    dans l'aperçu : aucune requête réseau, aucun logo tiers à s'approprier. */
export type Signe = "onde" | "pastilles" | "date";

export type AppApercu = {
  /** Nom propre : il ne se traduit pas, il ne vit donc pas dans les messages. */
  nom: string;
  contenu: CleContenu;
  signe: Signe;
};

/** Au moins deux apps : l'aperçu met en scène un relais, pas une vitrine. Le
    type le dit, donc vider le tableau ne compile pas. */
export type CoupleApercu = readonly [AppApercu, AppApercu, ...AppApercu[]];

export const APPS_APERCU = [
  { nom: "boringNotch", contenu: "musique", signe: "onde" },
  { nom: "Vibe Island", contenu: "agents", signe: "pastilles" },
] as const satisfies CoupleApercu;
