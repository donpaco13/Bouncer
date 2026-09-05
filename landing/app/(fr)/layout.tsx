import type { Metadata } from "next";
import type { ReactNode } from "react";
import { fr } from "@/content/fr";
import { FAVICON } from "@/content/liens";
import "../globals.css";

/* Une langue = un groupe de routes avec sa propre racine, donc son propre
   attribut `lang`. La version anglaise sera app/(en)/ sur ce modèle : trois
   lignes qui changent, et le dictionnaire. */
export const metadata: Metadata = {
  title: fr.meta.titre,
  description: fr.meta.description,
  icons: { icon: FAVICON },
};

export default function RacineFr({ children }: { children: ReactNode }) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
