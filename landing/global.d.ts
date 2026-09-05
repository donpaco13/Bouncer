import type messages from "./messages/fr.json";
import type { routing } from "./i18n/routing";

/* Le français est la langue de référence : c'est sa forme qui définit les clés.
   Une clé qui n'existe pas ne compile pas, et messages/parite.ts vérifie que
   les autres langues la couvrent. */
declare module "use-intl" {
  interface AppConfig {
    Locale: (typeof routing.locales)[number];
    Messages: typeof messages;
  }
}
