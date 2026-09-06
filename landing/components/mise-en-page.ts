/**
 * Les quelques compositions d'utilitaires Tailwind qui reviennent d'une section
 * à l'autre. Ce n'est pas une couche d'abstraction : c'est la colonne, le bloc
 * de texte, le titre et le chapô — les quatre mesures qui tiennent le rythme de
 * la page. Les répéter à la main, c'est les laisser diverger.
 */

/** La colonne de la page : 1040 px, centrée, 24 px de marge. */
export const enveloppe = "mx-auto max-w-[1040px] px-6";

/** La mesure de lecture : 34 rem, centrée. */
export const bloc = "mx-auto max-w-[34rem]";

/** Le corps de texte gris, avec ses renforts en encre pleine. */
export const corps = "[&_p]:text-gris [&_strong]:font-semibold [&_strong]:text-encre";

export const titre =
  "titre-degrade mx-auto mb-[.55em] text-balance text-center text-titre font-semibold leading-[1.08] tracking-titre";

export const chapo =
  "mx-auto my-0 max-w-[32rem] text-center text-chapo font-normal leading-[1.5] text-gris";

/** Une liste numérotée d'étapes d'installation. */
export const etapes =
  "mx-auto max-w-[34rem] list-decimal pl-[1.35em] text-gris marker:tabular-nums marker:text-sourdine [&>li]:mb-[.55em]";

/** Le cadre qui isole une carte, une citation ou une commande : le voile blanc
    de 4 % défini dans `globals.css`, jamais un fond plein. Sur du noir, une
    surface opaque plus claire que le fond se lit comme un trou. */
export const carte = "surface";

/** Le titre d'un bloc à l'intérieur d'une section. */
export const sousTitre =
  "mb-[.8em] text-[1.25rem] font-semibold tracking-[-.02em] text-encre";
