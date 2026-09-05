import type { ReactNode } from "react";
import type { Dictionary } from "@/content/dictionary";

export type Demo = Dictionary["demo"];

/** Les trois panneaux de démo, dans l'ordre du cycle. */
export const NB_PANNEAUX = 3;
export type Indice = 0 | 1 | 2;

/**
 * Un panneau d'app d'encoche : la pilule noire, plus large que l'encoche, avec
 * une colonne à gauche, le trou de l'encoche au milieu, une colonne à droite.
 * Volontairement générique — aucun nom d'app tierce, voir content/dictionary.ts.
 */
export function Panneau({
  i,
  demo,
  className,
}: {
  i: Indice;
  demo: Demo;
  className?: string;
}) {
  const contenu: [ReactNode, ReactNode][] = [
    [
      <>
        <span className="pastille vive" />
        <span className="pastille" />
        <span className="pastille" />
      </>,
      <span className="valeur">{demo.agents}</span>,
    ],
    [
      <span className="onde">
        {[5, 11, 7, 12].map((h, k) => (
          <i key={k} style={{ height: `${h}px` }} />
        ))}
      </span>,
      <span className="valeur">{demo.duree}</span>,
    ],
    [
      <span className="valeur">{demo.jour}</span>,
      <span className="valeur">{demo.heure}</span>,
    ],
  ];
  const [gauche, droite] = contenu[i];

  return (
    <div className={className ? `panneau ${className}` : "panneau"} data-i={i}>
      <span className="g">{gauche}</span>
      <span />
      <span className="d">{droite}</span>
    </div>
  );
}

/** Le rectangle noir de l'encoche : la forme constante de la page. Elle se
 *  place entre les panneaux et ce qui la surplombe (doigts, flèches). */
export function Encoche() {
  return <div className="encoche" />;
}

/** Le haut d'un écran de MacBook. */
export function Ecran(props: React.ComponentProps<"div">) {
  return <div className="ecran" {...props} />;
}
