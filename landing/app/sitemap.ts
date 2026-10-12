import type { MetadataRoute } from "next";
import { absolue, langues } from "@/content/seo";
import { routing } from "@/i18n/routing";

export const dynamic = "force-static";

/** Une entrée par langue, chacune avec ses équivalents hreflang. */
export default function sitemap(): MetadataRoute.Sitemap {
  const alternates = { languages: langues() as Record<string, string> };
  return routing.locales.map((l) => ({ url: absolue(`/${l}/`), alternates }));
}
