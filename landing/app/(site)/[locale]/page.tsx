import { notFound } from "next/navigation";
import { hasLocale } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { LIENS } from "@/content/liens";
import { absolue } from "@/content/seo";
import { Landing } from "@/components/landing";
import { routing } from "@/i18n/routing";

export default async function Page({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: "meta" });

  /* Les données structurées : ce que Google affiche d'une app. */
  const ld = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Bouncer",
    description: t("description"),
    url: absolue(`/${locale}/`),
    image: absolue(`/og/${locale}.png`),
    inLanguage: locale,
    applicationCategory: "UtilitiesApplication",
    operatingSystem: "macOS 14 or later",
    license: "https://opensource.org/licenses/MIT",
    downloadUrl: LIENS.versions,
    offers: { "@type": "Offer", price: "0", priceCurrency: "EUR" },
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(ld).replace(/</g, "\\u003c") }}
      />
      <Landing />
    </>
  );
}
