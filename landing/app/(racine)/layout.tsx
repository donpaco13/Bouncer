import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations } from "next-intl/server";
import { FAVICON, SITE } from "@/content/liens";
import { absolue, langues } from "@/content/seo";
import { routing } from "@/i18n/routing";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations({
    locale: routing.defaultLocale,
    namespace: "meta",
  });
  return {
    metadataBase: new URL(SITE),
    title: t("titre"),
    description: t("description"),
    icons: { icon: FAVICON },
    /* `/` n'est qu'un aiguillage vers la langue par défaut : la page à
       indexer est celle-là. */
    alternates: {
      canonical: absolue(`/${routing.defaultLocale}/`),
      languages: langues(),
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
