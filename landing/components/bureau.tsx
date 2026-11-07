"use client";

import { useEffect, useRef, useState } from "react";
import type { CSSProperties, ReactNode } from "react";
import type { Bascule } from "@/content/compatibilite";
import type { Signe } from "@/content/demo";
import { IconeMenu, Marque, SIGNES, largeur } from "./signes";

/** Une app de l'encoche, textes déjà résolus dans la langue de la page : aucun
    dictionnaire ne part au navigateur. */
export type AppBureau = {
  nom: string;
  valeur: string;
  signe: Signe;
  largeur: number;
  voie: Bascule;
  libelleVoie: string;
  /** Ce que le lecteur d'écran annonce, déjà composé avec le nom de l'app. */
  annonces: { rapide: string; relance: string; arrivee: string; allume: string };
};

export type LibellesBureau = {
  navigation: string;
  marque: string;
  menu: string;
  menuTitre: string;
  appSuivante: string;
  eteint: string;
  date: string;
  depot: string;
};

/** Le temps que met une app relancée à afficher sa fenêtre, à peu près celui
    mesuré sur boringNotch. Le passage de l'une à l'autre, une fois la nouvelle
    arrivée, est le même que pour une bascule instantanée : il vit dans le CSS
    (`.pill` et `.pill.show`). */
const RELANCE_MS = 950;

/**
 * LE HAUT DE LA PAGE EST LE HAUT DE L'ÉCRAN DU MAC.
 *
 * La barre des menus sert de navigation au site, l'encoche pend au milieu et
 * elle marche : clic, balayage à deux doigts, ⌃⌥⌘B, et le
 * menu de Bouncer en haut à droite, avec ● ○ ◐ et l'interrupteur. Ce sont les
 * vraies pièces de l'app, pas un panneau de test posé sous une illustration.
 *
 * Sur Mac, rien ne bouge tout seul. Chaque changement d'état vient d'un geste
 * du visiteur, et la voie relance montre la règle du moteur : l'app en place
 * reste affichée tant que la suivante n'est pas arrivée.
 *
 * Sur téléphone, personne n'a de trackpad sous la main : l'encoche tourne
 * seule, en CSS, jusqu'au premier geste (`.desk` sans `.used`). Ce geste
 * reprend la démo depuis l'app à l'écran, lue dans l'animation.
 *
 * Le texte du héros arrive en `children`, rendu au serveur.
 */
export function Bureau({
  apps,
  l,
  nav,
  langue,
  indice,
  children,
}: {
  apps: AppBureau[];
  l: LibellesBureau;
  /** `seulMac` : l'entrée vise une section absente de la page du téléphone. */
  nav: { href: string; libelle: string; seulMac?: boolean }[];
  langue: ReactNode;
  indice: ReactNode;
  children: ReactNode;
}) {
  const [cur, setCur] = useState(0);
  const [on, setOn] = useState(true);
  const [busy, setBusy] = useState(-1);
  const [touche, setTouche] = useState(false);
  const [ouvert, setOuvert] = useState(false);
  const [annonce, setAnnonce] = useState("");
  const scene = useRef<HTMLDivElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const boutonMenu = useRef<HTMLButtonElement>(null);
  const minuteries = useRef<number[]>([]);
  const dernier = useRef(0);
  const x0 = useRef<number | null>(null);

  const annuler = () => {
    minuteries.current.forEach(clearTimeout);
    minuteries.current = [];
  };
  useEffect(() => annuler, []);

  /* L'app que montre le cycle CSS du téléphone, lue dans la progression de
     l'animation de la première pastille. Sans cycle en cours (Mac, mouvement
     réduit, ou après le premier geste), c'est l'app courante. */
  const affichee = () => {
    if (touche) return cur;
    const cycle = scene.current
      ?.querySelector(".pill")
      ?.getAnimations()
      .find((a) => a instanceof CSSAnimation);
    const p = cycle?.effect?.getComputedTiming().progress;
    return typeof p === "number" ? Math.floor(p * apps.length) % apps.length : cur;
  };
  /* Le premier geste arrête le cycle et fige l'app qu'il montrait. */
  const reprendre = () => {
    const k = affichee();
    setTouche(true);
    setCur(k);
    return k;
  };

  function go(k: number, depuis = cur) {
    if (!on || busy >= 0 || k === depuis) return;
    setTouche(true);
    const a = apps[k];
    if (a.voie === "rapide") {
      setCur(k);
      setAnnonce(a.annonces.rapide);
      return;
    }
    // Voie relance : la nouvelle app démarre, l'ancienne ne part qu'une fois la nouvelle à l'écran
    setBusy(k);
    setAnnonce(a.annonces.relance);
    minuteries.current.push(
      window.setTimeout(() => {
        setCur(k);
        setBusy(-1);
        setAnnonce(a.annonces.arrivee);
      }, RELANCE_MS),
    );
  }
  const step = (d: number) => {
    const depuis = reprendre();
    go((depuis + d + apps.length) % apps.length, depuis);
  };
  /* Un balayage de trackpad émet des dizaines d'événements : un seul cran par
     demi-seconde, comme dans l'app. */
  const freine = (d: number) => {
    const t = Date.now();
    if (t - dernier.current > 500) {
      dernier.current = t;
      step(d);
    }
  };

  /* Les écouteurs globaux sont rebranchés à chaque rendu : ils lisent l'état
     courant sans référence à tenir à jour. */
  useEffect(() => {
    const touches = (e: KeyboardEvent) => {
      if (e.ctrlKey && e.altKey && e.metaKey && e.code === "KeyB") {
        e.preventDefault();
        step(1);
      }
      if (e.key === "Escape") setOuvert(false);
    };
    const dehors = (e: MouseEvent) => {
      const t = e.target as Node;
      if (!menu.current?.contains(t) && !boutonMenu.current?.contains(t)) setOuvert(false);
    };
    /* Le défilement horizontal du trackpad, c'est le balayage à deux doigts.
       `passive: false` pour l'empêcher de faire défiler la page. */
    const molette = (e: WheelEvent) => {
      if (Math.abs(e.deltaX) > Math.abs(e.deltaY) && Math.abs(e.deltaX) > 6) {
        e.preventDefault();
        freine(1);
      }
    };
    const s = scene.current;
    addEventListener("keydown", touches);
    document.addEventListener("click", dehors);
    s?.addEventListener("wheel", molette, { passive: false });
    return () => {
      removeEventListener("keydown", touches);
      document.removeEventListener("click", dehors);
      s?.removeEventListener("wheel", molette);
    };
  });

  const basculer = (allume: boolean) => {
    annuler();
    setOn(allume);
    setBusy(-1);
    setTouche(true);
    setAnnonce(allume ? apps[cur].annonces.allume : l.eteint);
  };

  const classes = ["stage", !on && "off", busy >= 0 && "wait"]
    .filter(Boolean)
    .join(" ");

  return (
    <div className={touche ? "desk used" : "desk"}>
      <nav className="menubar" aria-label={l.navigation}>
        <ul className="l">
          <li>
            <a className="mb brand" href="#top" aria-label={l.marque}>
              <Marque />
              <span className="bt">Bouncer</span>
            </a>
          </li>
          {/* La langue se range à droite, comme le menu de saisie de macOS. Sur
              téléphone, la colonne de droite n'a la place que pour le menu de
              Bouncer : la langue passe à gauche, à côté de la marque. */}
          <li className="lang-m">{langue}</li>
          {nav.map((n) => (
            <li key={n.href} className={n.seulMac ? "nav v-mac" : "nav"}>
              <a className="mb" href={n.href}>
                {n.libelle}
              </a>
            </li>
          ))}
        </ul>
        <span aria-hidden="true" />
        <ul className="r">
          <li>
            <button
              ref={boutonMenu}
              className="mb"
              type="button"
              aria-expanded={ouvert}
              aria-controls="bmenu"
              aria-label={l.menu}
              onClick={() => {
                /* Ouvrir le menu compte comme un premier geste : l'infobulle
                   s'efface, sinon elle passerait devant le menu sur téléphone. */
                reprendre();
                setOuvert((o) => !o);
              }}
            >
              <IconeMenu />
            </button>
          </li>
          <li className="lang-d">{langue}</li>
          <li className="gh">
            <a className="mb" href={l.depot}>
              GitHub
            </a>
          </li>
          <li className="date">
            <span className="mb" aria-hidden="true">
              {l.date}
            </span>
          </li>
          <li>
            <span className="mb time" aria-hidden="true">
              9:41
            </span>
          </li>
        </ul>
        <div className={ouvert ? "menu open" : "menu"} id="bmenu" ref={menu}>
          <p className="mt">{l.menuTitre}</p>
          {apps.map((a, k) => (
            <button key={a.nom} type="button" className="row" onClick={() => go(k)}>
              <span>{k === busy ? "◐" : on && k === cur ? "●" : "○"}</span>
              <span>{a.nom}</span>
              <small>{a.libelleVoie}</small>
            </button>
          ))}
          <hr />
          <label>
            Bouncer
            <input
              className="switch"
              type="checkbox"
              checked={on}
              onChange={(e) => basculer(e.target.checked)}
            />
          </label>
          <div className="k">
            <span>{l.appSuivante}</span>
            <span>⌃⌥⌘B</span>
          </div>
        </div>
      </nav>

      <div
        className={classes}
        ref={scene}
        style={{ "--cw": apps[cur].largeur } as CSSProperties}
        onTouchStart={(e) => (x0.current = e.touches[0].clientX)}
        onTouchEnd={(e) => {
          if (x0.current !== null && Math.abs(e.changedTouches[0].clientX - x0.current) > 24) freine(1);
          x0.current = null;
        }}
      >
        <span className="notch" aria-hidden="true" />
        {apps.map((a, k) => {
          const visible = !on || k === cur;
          return (
            <button
              key={a.nom}
              type="button"
              className={visible ? "pill show" : "pill"}
              style={{ ...largeur(a.largeur), "--i": k } as CSSProperties}
              tabIndex={-1}
              aria-hidden="true"
              onClick={() => step(1)}
            >
              <span className="t">{SIGNES[a.signe]}</span>
              <span className="t">{a.valeur}</span>
            </button>
          );
        })}
        {/* Sur téléphone, la plus large des pastilles déborde de quelques
            pixels sur le lien de langue et le menu. Le tap passe par cette
            zone, limitée à l'espace réservé à l'encoche : les commandes de la
            barre gardent leurs 44 px. */}
        <span className="zone" aria-hidden="true" onClick={() => step(1)} />
        {/* Les flèches sont des repères, comme dans l'app : elles signalent
            qu'une autre app attend, on ne clique pas dessus. */}
        <span className="arw p" aria-hidden="true">
          <span>‹</span>
        </span>
        <span className="arw n" aria-hidden="true">
          <span>›</span>
        </span>
        {/* Le cycle du téléphone : deux doigts balaient l'encoche avant chaque
            bascule, et la file ●○○ suit. Affiché seulement pendant le cycle. */}
        <span className="boucle" aria-hidden="true">
          <span className="doigts">
            <i />
            <i />
          </span>
          <span className="file">
            {apps.map((a, k) => (
              <i key={a.nom} style={{ "--i": k } as CSSProperties} />
            ))}
          </span>
        </span>
        <p className="hint v-mac" aria-hidden="true">
          <span className="fingers">
            <i />
            <i />
          </span>
          {indice}
        </p>
      </div>
      <p className="sr" aria-live="polite">
        {annonce}
      </p>

      {children}
    </div>
  );
}
