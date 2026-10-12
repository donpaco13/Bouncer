import type { Metadata } from "next";
import type { ReactNode } from "react";
import { notFound } from "next/navigation";
import { hasLocale } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { FAVICON, SITE } from "@/content/liens";
import { LOCALE_OG, absolue, langues } from "@/content/seo";
import { routing } from "@/i18n/routing";
import "../../globals.css";

type Params = { params: Promise<{ locale: string }> };

/* Une langue = un chemin pré-rendu, donc son propre attribut `lang`. Sans
   `generateStaticParams` et `setRequestLocale`, le rendu bascule en dynamique
   et l'export statique échoue. */
export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

/* Le segment attrape aussi les chemins inconnus : ce qui en sort n'est une
   langue que si on le vérifie. */
async function langueDe(params: Params["params"]) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  return locale;
}

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const locale = await langueDe(params);
  const t = await getTranslations({ locale, namespace: "meta" });
  const url = absolue(`/${locale}/`);
  const image = {
    url: absolue(`/og/${locale}.png`),
    width: 1200,
    height: 630,
    alt: t("ogAlt"),
  };
  return {
    metadataBase: new URL(SITE),
    title: t("titre"),
    description: t("description"),
    icons: { icon: FAVICON },
    alternates: { canonical: url, languages: langues() },
    openGraph: {
      type: "website",
      siteName: "Bouncer",
      url,
      title: t("titre"),
      description: t("description"),
      locale: LOCALE_OG[locale],
      alternateLocale: routing.locales.filter((l) => l !== locale).map((l) => LOCALE_OG[l]),
      images: [image],
    },
    twitter: {
      card: "summary_large_image",
      title: t("titre"),
      description: t("description"),
      images: [image],
    },
  };
}

export default async function Racine({
  children,
  params,
}: Params & { children: ReactNode }) {
  const locale = await langueDe(params);
  setRequestLocale(locale);

  return (
    <html lang={locale}>
      <body>{children}</body>
    </html>
  );
}
