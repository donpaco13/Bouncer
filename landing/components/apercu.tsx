"use client";

import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";

/** Ce que les pilules affichent, déjà traduit. Générique par construction :
    aucune app tierce n'est nommée ici. Le tableau des méthodes de bascule les
    nomme, lui, parce qu'il rend compte de mesures ; une démo jouable, non. */
export type Demo = {
  noms: [string, string, string];
  agents: string;
  duree: string;
  jour: string;
  heure: string;
};

/** Les libellés de l'aperçu qui ne sont pas des noms d'app. */
export type Libelles = {
  invite: string;
  enScene: string;
  debranche: string;
  bouncerActif: string;
  precedente: string;
  suivante: string;
  choisir: string;
  raccourci: string;
};

const NB = 3;
const INDICES = [0, 1, 2] as const;

/**
 * L'APERÇU VIVANT — le haut d'un MacBook, jouable à la souris et au clavier.
 *
 * C'est la première chose qu'on voit, et c'est le produit entier : trois apps
 * d'encoche installées, une seule en scène, et quatre façons d'en changer —
 * le Dock, les flèches sur le boîtier caméra, les flèches du clavier, et le
 * vrai raccourci de Bouncer (⌃⌥⌘B), qui marche ici comme il marchera là-bas.
 *
 * Rien ne se déclenche tout seul. Pas de minuterie, pas de scène qui se joue
 * devant un visiteur passif : la scène ne bouge que quand il la touche. Et
 * l'interrupteur débranche Bouncer pour montrer l'état sans lui — les trois
 * pilules au même endroit, illisibles. Le problème et sa solution tiennent
 * dans le même widget, et c'est le visiteur qui bascule de l'un à l'autre.
 */
export function ApercuVivant({ demo, l }: { demo: Demo; l: Libelles }) {
  const [actif, setActif] = useState(1);
  const [bouncer, setBouncer] = useState(true);
  const [touche, setTouche] = useState(false);

  const bascule = (sens: number) => {
    setActif((i) => (i + sens + NB) % NB);
    setBouncer(true);
    setTouche(true);
  };

  const choisir = (i: number) => {
    setActif(i);
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

  return (
    <figure
      className="apercu mt-10"
      data-bouncer={bouncer ? "on" : "off"}
      onKeyDown={surFleches}
    >
      <div className="mac">
        <div className="bureau">
          <BarreMenus />

          {INDICES.map((i) => (
            <Panneau
              key={i}
              i={i}
              demo={demo}
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

          <div className="dock">
            {INDICES.map((i) => (
              <button
                key={i}
                type="button"
                className="tuile"
                aria-pressed={bouncer && i === actif}
                aria-label={`${l.choisir} ${demo.noms[i]}`}
                title={demo.noms[i]}
                onClick={() => choisir(i)}
              >
                {ICONES[i]}
              </button>
            ))}
          </div>
        </div>
      </div>

      <figcaption className="pupitre">
        <span className="etat" aria-live="polite">
          <span className="puce" aria-hidden="true" />
          {bouncer ? (
            <span>
              {touche ? l.enScene : l.invite}{" "}
              <strong>{demo.noms[actif]}</strong>
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
    exactement ce qui se passe à l'écran, et ça explique pourquoi deux apps
    d'encoche ouvertes ensemble se marchent dessus.

    L'heure est 9:41 en dur, l'heure des présentations Apple. Elle ne se
    traduit pas et elle ne doit surtout pas reprendre celle du panneau
    calendrier : deux horloges différentes côte à côte se liraient comme un
    bug. Celle-ci est l'heure du système, celle du panneau est un rendez-vous. */
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

/** Une pilule d'app d'encoche : une colonne à gauche, le trou de l'encoche au
    milieu, une colonne à droite. */
function Panneau({
  i,
  demo,
  actif,
}: {
  i: 0 | 1 | 2;
  demo: Demo;
  actif: boolean;
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
    <div
      className={actif ? "panneau actif" : "panneau"}
      data-i={i}
      aria-hidden="true"
    >
      <span className="g">{gauche}</span>
      <span />
      <span className="d">{droite}</span>
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

/* Trois icônes de Dock, dans l'ordre des pilules : un suivi, un lecteur, un
   calendrier. Dessinées ici plutôt que chargées : aucune requête réseau, et
   aucun logo d'app tierce à s'approprier. */
const ICONES = [
  <svg key="0" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <path
      d="M3 17.5 8 11l4 3.2L21 5"
      stroke="currentColor"
      strokeWidth="1.9"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <circle cx="8" cy="11" r="1.9" fill="currentColor" />
    <circle cx="12" cy="14.2" r="1.9" fill="currentColor" />
  </svg>,
  <svg key="1" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <path
      d="M9 18V6.4l10-2v11.2"
      stroke="currentColor"
      strokeWidth="1.9"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <circle cx="6.6" cy="18" r="2.6" fill="currentColor" />
    <circle cx="16.6" cy="15.6" r="2.6" fill="currentColor" />
  </svg>,
  <svg key="2" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <rect
      x="3.2"
      y="5"
      width="17.6"
      height="15"
      rx="3"
      stroke="currentColor"
      strokeWidth="1.9"
    />
    <path
      d="M3.2 10h17.6M8.4 3v4M15.6 3v4"
      stroke="currentColor"
      strokeWidth="1.9"
      strokeLinecap="round"
    />
    <circle cx="8.6" cy="14.4" r="1.5" fill="currentColor" />
  </svg>,
];
