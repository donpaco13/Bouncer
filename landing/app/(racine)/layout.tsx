import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations } from "next-intl/server";
import { FAVICON } from "@/content/liens";
import { routing } from "@/i18n/routing";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations({
    locale: routing.defaultLocale,
    namespace: "meta",
  });
  return {
    title: t("titre"),
    description: t("description"),
    icons: { icon: FAVICON },
    alternates: {
      canonical: "/",
      languages: {
        en: "/en/",
        fr: "/fr/",
        "x-default": `/${routing.defaultLocale}/`,
      },
    },
    openGraph: {
      title: t("titre"),
      description: t("description"),
      locale: routing.defaultLocale === "fr" ? "fr_FR" : "en_US",
      alternateLocale: routing.defaultLocale === "fr" ? ["en_US"] : ["fr_FR"],
    },
  };
}

/* La page d'aiguillage a sa propre racine HTML : elle ne partage rien avec le
   site, pas même la feuille de style. */
export default function RacineAiguillage({ children }: { children: ReactNode }) {
  return (
    <html lang={routing.defaultLocale}>
      <body>{children}</body>
    </html>
  );
}
