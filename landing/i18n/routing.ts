import { defineRouting } from "next-intl/routing";

/* Le préfixe de langue est obligatoire, et ce n'est pas un choix : en export
   statique il n'y a pas de proxy pour réécrire `/` vers la langue par défaut,
   donc chaque langue doit avoir son propre chemin pré-rendu. Le français reste
   la langue de référence — `/` renvoie vers `/fr/` (voir app/(racine)/page.tsx),
   et la négociation par en-tête Accept-Language n'existe pas ici. */
export const routing = defineRouting({
  locales: ["fr", "en"],
  defaultLocale: "fr",
  localePrefix: "always",
  localeDetection: false,
});

export type Langue = (typeof routing.locales)[number];

/** Ce qu'affiche le sélecteur. Le nom d'une langue s'écrit dans cette langue. */
export const NOMS_LANGUES: Record<Langue, string> = {
  fr: "Français",
  en: "English",
};
