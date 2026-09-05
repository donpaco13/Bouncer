import type { ReactNode } from "react";
import { routing } from "@/i18n/routing";

/* La page d'aiguillage a sa propre racine HTML : elle ne partage rien avec le
   site, pas même la feuille de style. */
export default function RacineAiguillage({ children }: { children: ReactNode }) {
  return (
    <html lang={routing.defaultLocale}>
      <body>{children}</body>
    </html>
  );
}
