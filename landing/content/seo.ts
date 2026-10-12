import type { Metadata } from "next";
import { routing, type Langue } from "@/i18n/routing";
import { SITE } from "./liens";

/** Chemin du site → URL absolue. Les balises meta, le sitemap, le JSON-LD et
    robots.txt passent tous par ici : une seule façon de fabriquer une URL. */
export const absolue = (chemin: string) => `${SITE}${chemin}`;

/** Les liens hreflang d'une page : une entrée par langue, plus x-default. */
export function langues(): NonNullable<Metadata["alternates"]>["languages"] {
  return {
    ...Object.fromEntries(routing.locales.map((l) => [l, absolue(`/${l}/`)])),
    "x-default": absolue(`/${routing.defaultLocale}/`),
  };
}

export const LOCALE_OG: Record<Langue, string> = { en: "en_GB", fr: "fr_FR" };
