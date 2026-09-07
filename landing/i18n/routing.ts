import { defineRouting } from "next-intl/routing";

/* Le préfixe de langue est obligatoire, et ce n'est pas un choix : en export
   statique il n'y a pas de proxy pour réécrire `/` vers la langue par défaut,
   donc chaque langue doit avoir son propre chemin pré-rendu. L'anglais est
   la langue par défaut — `/` renvoie vers `/en/` (voir app/(racine)/page.tsx),
   et la négociation par en-tête Accept-Language n'existe pas ici. */
export const routing = defineRouting({
  locales: ["en", "fr"],
  defaultLocale: "en",
  localePrefix: "always",
  localeDetection: false,
});

export type Langue = (typeof routing.locales)[number];

/** Ce qu'affiche le sélecteur. Le nom d'une langue s'écrit dans cette langue. */
export const NOMS_LANGUES: Record<Langue, string> = {
  fr: "Français",
  en: "English",
};
