import createNextIntlPlugin from "next-intl/plugin";
import type { NextConfig } from "next";

/* Landing statique : `next build` écrit un site servable tel quel dans out/.
   Pas d'images distantes, pas de runtime — le fichier de référence n'en avait
   pas non plus, et on ne veut pas d'un serveur pour une page. */
/* Servie par GitHub Pages sous https://donpaco13.github.io/Bouncer : tout vit sous /Bouncer.
   Seulement en production, pour que `next dev` reste sur localhost:3000/. Même valeur que
   le chemin de SITE (content/liens.ts). */
const base = process.env.NODE_ENV === "production" ? "/Bouncer" : "";

const config: NextConfig = {
  output: "export",
  basePath: base,
  assetPrefix: base,
  trailingSlash: true,
  images: { unoptimized: true },
};

export default createNextIntlPlugin("./i18n/request.ts")(config);
