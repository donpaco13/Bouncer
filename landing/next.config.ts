import type { NextConfig } from "next";

/* Landing statique : `next build` écrit un site servable tel quel dans out/.
   Pas d'images distantes, pas de runtime — le fichier de référence n'en avait
   pas non plus, et on ne veut pas d'un serveur pour une page. */
const config: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
};

export default config;
