"use client";

import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import type { Signe } from "@/content/demo";

/** Une app de la scène, texte déjà résolu dans la langue de la page. */
export type AppDemo = {
  nom: string;
  valeur: string;
  signe: Signe;
};

/** Les libellés de l'aperçu qui ne sont pas des noms d'app. */
export type Libelles = {
  invite: string;
  enScene: string;
  debranche: string;
  bouncerActif: string;
  precedente: string;
  suivante: string;
  geste: string;
  raccourci: string;
};

/** Au-delà de ce déplacement horizontal, un cliquer-glisser est un swipe. */
const SEUIL_GESTE = 26;

/**
 * L'APERÇU — L'ENCOCHE, ET RIEN D'AUTRE.
 *
 * Un gros plan sur le haut de l'écran, et deux apps d'encoche qui se relaient
 * dans le même rectangle. Pas de MacBook entier, pas de bureau, pas de Dock
 * avec des applications alignées en dessous : cette grammaire-là raconte un
 * couteau suisse, et Bouncer ne fait qu'une chose. Une idée, un geste.
 *
 * Le geste est la commande principale, et c'est le vrai : on tire
 * horizontalement sur la scène, comme on balaie l'encoche à deux doigts. Trois
 * doublures pour ceux qui ne peuvent pas ou ne veulent pas glisser — les
 * flèches du boîtier caméra, les flèches du clavier, et le raccourci global
 * ⌃⌥⌘B, qui marche ici comme il marchera après l'installation.
 *
 * Rien ne se déclenche tout seul. Pas de minuterie, pas de scène qui se joue
 * devant un visiteur passif. Et l'interrupteur débranche Bouncer pour montrer
 * l'état sans lui : les deux pilules au même endroit, illisibles. Le problème
 * et sa solution tiennent dans le même widget.
 */
export function ApercuVivant({ apps, l }: { apps: AppDemo[]; l: Libelles }) {
  const nb = apps.length;
  const [actif, setActif] = useState(0);
  const [sens, setSens] = useState(1);
  const [bouncer, setBouncer] = useState(true);
  const [touche, setTouche] = useState(false);
  const depart = useRef<number | null>(null);

  const bascule = (direction: number) => {
    setSens(direction);
    setActif((i) => (i + direction + nb) % nb);
    setBouncer(true);
    setTouche(true);
  };

  /* Le vrai raccourci global de Bouncer, branché sur la page. Le visiteur qui
     l'essaie ici a déjà appris le geste qu'il fera après l'installation. */
  useEffect(() => {
    const surTouche = (e: KeyboardEvent) => {
      if (e.code === "KeyB" && e.ctrlKey && e.altKey && e.metaKey) {
        e.preventDefault();
        bascule(1);
      }
    };
    addEventListener("keydown", surTouche);
    return () => removeEventListener("keydown", surTouche);
  }, []);

  /* Les flèches du clavier, quand le focus est sur une commande de l'aperçu.
     L'événement remonte des boutons : pas de div focalisable à inventer. */
  const surFleches = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowLeft") bascule(-1);
    else if (e.key === "ArrowRight") bascule(1);
    else return;
    e.preventDefault();
  };

  /* Le swipe. Un pointeur qui part et qui revient au même endroit est un clic,
     et un clic avance aussi d'un cran : le visiteur qui n'a pas compris qu'on
     tirait obtient quand même la démonstration. */
  const surDebut = (e: React.PointerEvent) => {
    depart.current = e.clientX;
  };
  const surFin = (e: React.PointerEvent) => {
    const x0 = depart.current;
    depart.current = null;
    if (x0 === null) return;
    /* Les flèches et la piste sont dans la scène et leur clic remonte jusqu'ici.
       Sans ce garde-fou, un clic dessus avancerait de deux crans. */
    if ((e.target as HTMLElement).closest("button")) return;
    const dx = e.clientX - x0;
    if (Math.abs(dx) < SEUIL_GESTE) bascule(1);
    else bascule(dx < 0 ? 1 : -1);
  };

  return (
    <figure
      className="apercu mt-12"
      data-bouncer={bouncer ? "on" : "off"}
      style={{ "--sens": sens } as React.CSSProperties}
      onKeyDown={surFleches}
    >
      <div
        className="ecran"
        onPointerDown={surDebut}
        onPointerUp={surFin}
        onPointerCancel={() => (depart.current = null)}
      >
        <BarreMenus />

        {apps.map((app, i) => (
          <Pilule
            key={app.nom}
            i={i}
            app={app}
            actif={bouncer ? i === actif : true}
          />
        ))}

        <div className="encoche" aria-hidden="true" />
        <div className="lentille" aria-hidden="true" />

        <button
          type="button"
          className="fleche gauche"
          onClick={() => bascule(-1)}
          aria-label={l.precedente}
        >
          <Chevron sens={-1} />
        </button>
        <button
          type="button"
          className="fleche droite"
          onClick={() => bascule(1)}
          aria-label={l.suivante}
        >
          <Chevron sens={1} />
        </button>

        <button type="button" className="piste" onClick={() => bascule(1)}>
          <SigneDeuxDoigts />
          {l.geste}
        </button>
      </div>

      <figcaption className="pupitre">
        <span className="etat" aria-live="polite">
          <span className="puce" aria-hidden="true" />
          {bouncer ? (
            <span>
              {touche ? l.enScene : l.invite}{" "}
              <strong>{apps[actif].nom}</strong>
            </span>
          ) : (
            <span>{l.debranche}</span>
          )}
        </span>
        <span className="commandes">
          <span className="hidden sm:inline">
            <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>B</kbd>{" "}
            <span className="ml-1">{l.raccourci}</span>
          </span>
          <button
            type="button"
            className="interrupteur"
            aria-pressed={bouncer}
            onClick={() => {
              setBouncer((b) => !b);
              setTouche(true);
            }}
          >
            <span className="rail" aria-hidden="true" />
            {l.bouncerActif}
          </button>
        </span>
      </figcaption>
    </figure>
  );
}

/* ------------------------------------------------------------------ pièces */

/** La barre des menus de macOS. La pilule d'app la recouvre en partie : c'est
    exactement ce qui se passe à l'écran, et ça explique d'un coup d'œil
    pourquoi deux apps d'encoche ouvertes ensemble se marchent dessus.

    L'heure est 9:41 en dur, l'heure des présentations Apple. Elle ne se
    traduit pas. */
function BarreMenus() {
  return (
    <div className="barre-menus" aria-hidden="true">
      <span className="menus">
        <span className="fort">Finder</span>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
      </span>
      <span className="etat">
        <svg viewBox="0 0 16 12" width="15" height="11" fill="none">
          <path
            d="M1 4.2A9.6 9.6 0 0 1 15 4.2M3.4 6.9a6.2 6.2 0 0 1 9.2 0M6 9.5a2.7 2.7 0 0 1 4 0"
            stroke="currentColor"
            strokeWidth="1.2"
            strokeLinecap="round"
          />
        </svg>
        <svg viewBox="0 0 24 12" width="21" height="11" fill="none">
          <rect
            x="0.6"
            y="1.6"
            width="19"
            height="8.8"
            rx="2.6"
            stroke="currentColor"
            strokeWidth="1.1"
          />
          <rect x="2.3" y="3.3" width="12" height="5.4" rx="1.4" fill="currentColor" />
          <path
            d="M21.4 4.4v3.2"
            stroke="currentColor"
            strokeWidth="1.6"
            strokeLinecap="round"
          />
        </svg>
        <span>9:41</span>
      </span>
    </div>
  );
}

/** Une pilule d'app d'encoche : le nom de l'app et son signe à gauche, le trou
    de l'encoche au milieu, sa valeur du moment à droite. Toutes les pilules
    occupent la même case — c'est tout le sujet de la page. */
function Pilule({
  i,
  app,
  actif,
}: {
  i: number;
  app: AppDemo;
  actif: boolean;
}) {
  return (
    <div
      className={actif ? "pilule actif" : "pilule"}
      style={{ "--i": i } as React.CSSProperties}
      aria-hidden="true"
    >
      <span className="g">
        {SIGNES[app.signe]}
        <span className="nom">{app.nom}</span>
      </span>
      <span />
      <span className="d">
        <span className="valeur">{app.valeur}</span>
      </span>
    </div>
  );
}

function Chevron({ sens }: { sens: -1 | 1 }) {
  return (
    <svg viewBox="0 0 9 14" fill="none" aria-hidden="true">
      <path
        d={sens === -1 ? "M7.5 1 1.5 7l6 6" : "M1.5 1l6 6-6 6"}
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

/** Deux doigts et le va-et-vient qu'ils font. C'est le seul pictogramme de la
    scène, et il désigne la seule commande. */
function SigneDeuxDoigts() {
  return (
    <svg viewBox="0 0 26 14" width="26" height="14" fill="none" aria-hidden="true">
      <path
        d="M8 7h10"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      <path
        d="M11 3.6 7.4 7l3.6 3.4M15 3.6 18.6 7 15 10.4"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="2.6" cy="7" r="1.6" fill="currentColor" />
      <circle cx="23.4" cy="7" r="1.6" fill="currentColor" />
    </svg>
  );
}

/* Les signes des pilules, dessinés ici plutôt que chargés : aucune requête
   réseau, et aucun logo d'app tierce à s'approprier. La clé vient de
   `content/demo.ts` — ajouter une app, c'est ajouter une entrée ici. */
const SIGNES: Record<Signe, ReactNode> = {
  onde: (
    <span className="onde">
      {[5, 12, 7, 13, 9].map((h, k) => (
        <i key={k} style={{ height: `${h}px` }} />
      ))}
    </span>
  ),
  pastilles: (
    <span className="flex items-center gap-[4px]">
      <span className="pastille vive" />
      <span className="pastille" />
      <span className="pastille" />
    </span>
  ),
  date: (
    <svg viewBox="0 0 14 14" width="13" height="13" fill="none" aria-hidden="true">
      <rect
        x="1"
        y="2.4"
        width="12"
        height="10.6"
        rx="2.2"
        stroke="currentColor"
        strokeWidth="1.3"
      />
      <path
        d="M1 6h12M4.6 1v2.6M9.4 1v2.6"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
      />
    </svg>
  ),
};
