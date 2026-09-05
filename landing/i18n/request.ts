import { hasLocale } from "next-intl";
import { getRequestConfig } from "next-intl/server";
import { routing } from "./routing";

/* `requestLocale` vient du segment [locale]. Il peut être absent ou invalide
   (le segment attrape aussi les chemins inconnus), d'où le repli explicite. */
export default getRequestConfig(async ({ requestLocale }) => {
  const demande = await requestLocale;
  const locale = hasLocale(routing.locales, demande)
    ? demande
    : routing.defaultLocale;

  return {
    locale,
    messages: (await import(`../messages/${locale}.json`)).default,
  };
});
