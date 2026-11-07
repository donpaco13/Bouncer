import type { CSSProperties, ReactNode } from "react";
import type { Signe } from "@/content/demo";

/* Les signes des pastilles, dessinés ici plutôt que chargés : aucune requête
   réseau, et aucun logo d'app tierce à s'approprier. La clé vient de
   `content/demo.ts`. Ajouter une app à la démo, c'est ajouter un dessin ici. */
export const SIGNES: Record<Signe, ReactNode> = {
  pastilles: (
    <svg viewBox="0 0 40 10" aria-hidden="true">
      <circle cx="5" cy="5" r="4" fill="#30d158" />
      <circle cx="15" cy="5" r="4" fill="#30d158" />
      <circle cx="25" cy="5" r="4" fill="#ffd60a" />
      <circle cx="35" cy="5" r="4" fill="#64d2ff" />
    </svg>
  ),
  onde: (
    <svg viewBox="0 0 27 16" aria-hidden="true">
      <g fill="#ff9f0a">
        <rect x="0" y="5" width="3" height="6" rx="1.5" />
        <rect x="6" y="2" width="3" height="12" rx="1.5" />
        <rect x="12" y="0" width="3" height="16" rx="1.5" />
        <rect x="18" y="3" width="3" height="10" rx="1.5" />
        <rect x="24" y="6" width="3" height="4" rx="1.5" />
      </g>
    </svg>
  ),
  tiroir: (
    <svg viewBox="0 0 16 16" aria-hidden="true">
      <rect x="1" y="3" width="14" height="11" rx="2.5" fill="none" stroke="#bf5af2" strokeWidth="2" />
      <path d="M1 6h14" stroke="#bf5af2" strokeWidth="2" />
    </svg>
  ),
};

/** La largeur d'une pastille, en multiples de la largeur de l'encoche. Une
    propriété CSS personnalisée : le CSS en tire la largeur dépliée. */
export const largeur = (w: number) => ({ "--w": w }) as CSSProperties;

/** Une pastille dessinée, sans interaction : celle des scènes de la page. */
export function Pastille({
  signe,
  valeur,
  w,
  i,
  className = "",
}: {
  signe: Signe;
  valeur: string;
  w: number;
  /** Le rang dans un cycle animé : il décale l'animation de la pastille. */
  i?: number;
  className?: string;
}) {
  return (
    <span className={`pill ${className}`} style={{ ...largeur(w), "--i": i } as CSSProperties}>
      <span className="t">{SIGNES[signe]}</span>
      <span className="t">{valeur}</span>
    </span>
  );
}

/** Le logo : l'encoche, et la pastille rangée dessous. */
export function Marque() {
  return (
    <svg className="mark" viewBox="0 0 22 14" aria-hidden="true">
      <path d="M0 0h22v3.5a2.5 2.5 0 0 1-2.5 2.5h-17A2.5 2.5 0 0 1 0 3.5z" />
      <rect x="5" y="9" width="12" height="3" rx="1.5" opacity=".55" />
    </svg>
  );
}

export function Pomme() {
  return (
    <svg viewBox="0 0 17 20" aria-hidden="true">
      <path d="M14.1 10.6c0-2.5 2-3.7 2.1-3.8-1.2-1.7-3-1.9-3.6-2-1.5-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.5-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.3.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.8-1.1-2.8-4.1zM11.6 3.1c.7-.9 1.2-2 1.1-3.1-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.9-1.1 3 1.1.1 2.2-.6 2.9-1.4z" />
    </svg>
  );
}

/** L'icône de Bouncer dans la barre des menus : l'encoche et la file ● ○ ○. */
export function IconeMenu() {
  return (
    <svg viewBox="0 0 18 14" width="18" height="14" aria-hidden="true">
      <path d="M1 0h16v3a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2z" />
      <circle cx="5" cy="10" r="2" />
      <circle cx="9" cy="10" r="2" opacity=".45" />
      <circle cx="13" cy="10" r="2" opacity=".45" />
    </svg>
  );
}
