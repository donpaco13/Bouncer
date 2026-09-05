"use client";

import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { type Demo, Ecran, Encoche, NB_PANNEAUX, Panneau } from "./encoche";
import * as m from "./mise-en-page";
import { useMouvementReduit } from "./mouvement";

const INDICES = [0, 1, 2] as const;

/* ===========================================================================
   HÉROS — la superposition littérale, puis sa résolution.

   Les deux panneaux occupent exactement le même rectangle : « 4 agents » et
   « 2:41 » s'écrivent l'un sur l'autre. Ça se lit comme un bug d'affichage,
   et c'est précisément le problème que macOS laisse à l'utilisateur. Puis un
   panneau s'efface.
   =========================================================================== */
export function SceneHeros({
  demo,
  avant,
  apres,
}: {
  demo: Demo;
  avant: string;
  apres: string;
}) {
  const reduit = useMouvementReduit();
  const [resolu, setResolu] = useState(false);

  useEffect(() => {
    if (reduit) {
      setResolu(true);
      return;
    }
    const t = setTimeout(() => setResolu(true), 2400);
    return () => clearTimeout(t);
  }, [reduit]);

  return (
    <figure className="scene" data-etat={resolu ? "resolu" : undefined}>
      <Ecran aria-hidden="true">
        <Panneau i={0} demo={demo} />
        <Panneau i={1} demo={demo} />
        <Encoche />
      </Ecran>
      <figcaption className="legende">
        <span className="a">{avant}</span>
        <span className="b">{apres}</span>
      </figcaption>
    </figure>
  );
}

/* ===========================================================================
   LE GESTE — piloté par le DÉFILEMENT de l'utilisateur, jamais par un timer.

   Les deux doigts traversent l'encoche à la vitesse de son scroll, et l'app
   change quand ils l'ont traversée. Le mouvement répond à une action au lieu
   de se déclencher tout seul : c'est l'idée forte de la page.

   Titre et sous-titre sont DANS le bloc collant, sinon la scène reste seule à
   l'écran sur 280 vh sans rien qui la nomme.
   =========================================================================== */
export function SceneGeste({
  demo,
  titre,
  sousTitre,
}: {
  demo: Demo;
  titre: string;
  sousTitre: ReactNode;
}) {
  const reduit = useMouvementReduit();
  const piste = useRef<HTMLDivElement>(null);
  const doigts = useRef<HTMLDivElement>(null);
  const [actif, setActif] = useState(0);

  useEffect(() => {
    const cadre = piste.current;
    const main = doigts.current;
    if (reduit || !cadre || !main) return;

    let enAttente = false;

    const rendre = () => {
      enAttente = false;
      const haut = cadre.getBoundingClientRect().top;
      const course = cadre.offsetHeight - window.innerHeight;
      const p = course > 0 ? Math.min(1, Math.max(0, -haut / course)) : 0;
      const i = Math.min(NB_PANNEAUX - 1, Math.floor(p * NB_PANNEAUX));
      const sous = Math.min(1, p * NB_PANNEAUX - i);

      // React ignore un setState de valeur identique : la boucle à 60 images
      // par seconde ne provoque un rendu que sur un vrai changement d'app.
      setActif(i);

      // les deux doigts traversent l'encoche à l'intérieur de chaque segment
      main.style.transform = `translateX(${-22 + (sous * 2 - 1) * 66}px)`;
      main.style.opacity = String(
        Math.sin(Math.min(1, sous * 1.6) * Math.PI) * 0.9,
      );
    };

    const surDefilement = () => {
      if (!enAttente) {
        enAttente = true;
        requestAnimationFrame(rendre);
      }
    };

    addEventListener("scroll", surDefilement, { passive: true });
    addEventListener("resize", rendre, { passive: true });
    rendre();
    return () => {
      removeEventListener("scroll", surDefilement);
      removeEventListener("resize", rendre);
    };
  }, [reduit]);

  return (
    <div className="piste" ref={piste}>
      <div className="collant">
        <div className={m.enveloppe}>
          <h2 className={m.titre}>{titre}</h2>
          <p className={m.chapo}>{sousTitre}</p>
        </div>
        <Ecran aria-hidden="true">
          {INDICES.map((i) => (
            <Panneau
              key={i}
              i={i}
              demo={demo}
              className={i === actif ? "actif" : i < actif ? "avant" : ""}
            />
          ))}
          <Encoche />
          <div className="doigts" ref={doigts}>
            <i />
            <i />
          </div>
        </Ecran>
        <p className="legende" aria-live="polite">
          <span className="a" style={{ opacity: 1 }}>
            {demo.noms[actif]}
          </span>
        </p>
        <div className="jauge" aria-hidden="true">
          {INDICES.map((i) => (
            <i key={i} className={i === actif ? "on" : undefined} />
          ))}
        </div>
      </div>
    </div>
  );
}

/* ===========================================================================
   LES FLÈCHES — le même mécanisme, déclenché au clic ou au clavier. C'est le
   repli qui montre quand même la bascule quand le mouvement est réduit.
   =========================================================================== */
export function SceneFleches({
  demo,
  precedente,
  suivante,
}: {
  demo: Demo;
  precedente: string;
  suivante: string;
}) {
  const [actif, setActif] = useState(0);
  const bascule = (sens: number) =>
    setActif((i) => (i + sens + NB_PANNEAUX) % NB_PANNEAUX);

  return (
    <figure className="scene">
      <Ecran>
        {INDICES.map((i) => (
          <Panneau
            key={i}
            i={i}
            demo={demo}
            className={i === actif ? "actif" : ""}
          />
        ))}
        <Encoche />
        <button
          className="fleche gauche"
          onClick={() => bascule(-1)}
          aria-label={precedente}
        >
          <Chevron sens={-1} />
        </button>
        <button
          className="fleche droite"
          onClick={() => bascule(1)}
          aria-label={suivante}
        >
          <Chevron sens={1} />
        </button>
      </Ecran>
      <figcaption className="legende" aria-live="polite">
        <span className="a" style={{ opacity: 1 }}>
          {demo.noms[actif]}
        </span>
      </figcaption>
    </figure>
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
