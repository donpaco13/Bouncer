import type { ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";
import { CAMPAGNE, COMPATIBILITE, type LigneCompatibilite } from "@/content/compatibilite";
import { APPS_APERCU, appDemo } from "@/content/demo";
import { COMMANDE_BREW, LIENS } from "@/content/liens";
import { absolue } from "@/content/seo";
import { VIDEO, videoPrete } from "@/content/video";
import { NOMS_LANGUES, routing } from "@/i18n/routing";
import { BoutonCopie, LigneCommande } from "./actions";
import { Bureau, type AppBureau } from "./bureau";
import { Pastille, Pomme } from "./signes";

/* Les balises que le texte traduit a le droit de porter. Elles restent dans le
   code : une traduction choisit où le renfort tombe dans sa phrase, pas de quoi
   il est fait. Le lien prend son URL ici : content/liens.ts est la seule
   source, dans toutes les langues. */
const fort = (c: ReactNode) => <strong>{c}</strong>;
const code = (c: ReactNode) => <code>{c}</code>;
const lienVers = (href: string) => (c: ReactNode) => <a href={href}>{c}</a>;

/**
 * La page entière. Elle ne connaît pas la langue : `useTranslations` la lit
 * dans le segment [locale] et rend le dictionnaire correspondant. La version
 * anglaise est le même arbre avec d'autres chaînes, pas une seconde copie du
 * balisage.
 *
 * L'ordre des sections répond aux questions dans l'ordre où on se les pose :
 * qu'est-ce que ça fait (on le voit, on y joue), pourquoi j'en ai besoin,
 * comment je m'en sers, est-ce que ça marche chez moi (la deuxième question
 * de tout le monde, et le héros y renvoie), est-ce que ça peut rater, comment
 * je l'installe. La page finit sur l'installation.
 */
export function Landing() {
  const t = useTranslations();
  const locale = useLocale();
  const autre = routing.locales.find((x) => x !== locale) ?? routing.defaultLocale;

  /* Le bureau est un composant client : il reçoit des chaînes déjà résolues,
     donc aucun dictionnaire ne part au navigateur. */
  const apps: AppBureau[] = APPS_APERCU.map((a) => {
    const { app, bascule } = appDemo(a.cle);
    return {
      nom: app,
      valeur: t(`demo.contenus.${a.contenu}.valeur`),
      signe: a.signe,
      largeur: a.largeur,
      voie: bascule,
      libelleVoie: t(`compatibilite.${LIBELLE_BASCULE[bascule]}`),
      annonces: {
        rapide: t("apercu.annonceRapide", { app }),
        relance: t("apercu.annonceRelance", { app }),
        arrivee: t("apercu.annonceArrivee", { app }),
        allume: t("apercu.annonceAllume", { app }),
      },
    };
  });

  const [va, bn] = apps;
  /* La pastille que montrent les scènes de la page : la première app du cycle. */
  const vitrine = { signe: va.signe, valeur: va.valeur };
  /* Le texte est en anglais britannique, la date suit. */
  const dateCampagne = new Intl.DateTimeFormat(locale === "en" ? "en-GB" : locale, {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(CAMPAGNE));

  return (
    <>
      <a className="skip" href="#main">
        {t("chrome.evitement")}
      </a>

      <header className="hero">
        <Bureau
          apps={apps}
          l={{
            navigation: t("chrome.navigation"),
            marque: t("chrome.marque"),
            menu: t("apercu.menu"),
            menuTitre: t("apercu.menuTitre"),
            appSuivante: t("apercu.appSuivante"),
            eteint: t("apercu.annonceEteint"),
            date: t("chrome.date"),
            depot: LIENS.depot,
          }}
          nav={NAV.map(([href, cle]) => ({ href, libelle: t(`chrome.nav.${cle}`) }))}
          langue={
            /* Deux langues, donc un seul lien : celui vers l'autre, écrit dans
               l'autre. Relatif, parce que `trailingSlash` garantit que l'URL
               courante finit par « / » : le site marche servi d'un sous-dossier. */
            <a className="mb" href={`../${autre}/`} lang={autre} hrefLang={autre} aria-label={NOMS_LANGUES[autre]}>
              {autre.toUpperCase()}
            </a>
          }
          indice={t.rich("apercu.indice", { kbd: (c) => <kbd>{c}</kbd> })}
        >
          <div className="intro" id="top">
            {/* Deux variantes, choisies par le CSS selon le pointeur : `.v-mac`
                pour la souris et le trackpad, `.v-tel` pour le doigt. */}
            <p className="eyebrow v-mac">{t("heros.surtitre")}</p>
            <h1>
              {t("heros.titreLigne1")}
              <br />
              {t("heros.titreLigne2")}
            </h1>
            <p className="who v-mac">{t("heros.pourQui")}</p>
            <p className="who v-tel">{t("heros.resume")}</p>
            <div className="cta">
              <a className="btn mac v-mac" href="#install">
                <Pomme />
                {t("heros.installer")}
              </a>
              {/* Sur téléphone, un bouton d'installation d'app Mac ne mène
                  nulle part : on propose d'envoyer l'adresse au Mac. */}
              <div className="ailleurs v-tel">
                <p>{t("heros.surMac")}</p>
                <BoutonCopie
                  className="btn"
                  partage
                  texte={absolue(`/${locale}/`)}
                  copier={t("heros.envoyer")}
                  copie={t("heros.lienCopie")}
                  echec={t("heros.echecLien")}
                />
                <a className="link" href={LIENS.depot}>
                  {t("heros.voirCode")}
                </a>
              </div>
              <a className="link v-mac" href="#apps">
                {t("heros.voirCompatibles")}
              </a>
            </div>
            <p className="fine v-mac">{t.rich("heros.mentions", { lien: lienVers(LIENS.depot) })}</p>
            <p className="fine v-tel">{t("heros.mentionsTel")}</p>
          </div>

          <svg className="hills" viewBox="0 0 1440 190" preserveAspectRatio="none" aria-hidden="true">
            <path d="M0 120C180 70 330 60 520 96s330 40 520-6 300-50 400-20V190H0z" fill="#2b2466" opacity=".55" />
            <path d="M0 150c210-46 420-40 640-8s420 20 560-14 180-20 240-8V190H0z" fill="#8e86b8" opacity=".55" />
            <path d="M0 176c260-28 520-30 760-12s470 10 680-8V190H0z" fill="#e8e8ed" />
          </svg>
        </Bureau>
      </header>

      <main id="main" tabIndex={-1}>
        {/* --------------------------- LE PROBLÈME ------------------------
            Le conflit dessiné en éclaté : deux pastilles décalées en
            profondeur, chacune nommée, au-dessus de la même encoche. En face,
            la même encoche avec Bouncer. */}
        <section className="paper" id="problem">
          {/* La démo du héros est une simulation : la vidéo est la preuve.
              Muette, en boucle, sans son à couper. Tant qu'elle n'est pas
              tournée, rien ne s'affiche : un cadre vide qui promet une vidéo
              coûte un écran et fait chantier. */}
          {videoPrete() ? (
            <figure className="wrap film">
              <video
                className="ecran"
                src={`../${VIDEO.mp4}`}
                poster={`../${VIDEO.poster}`}
                aria-label={t("video.description")}
                autoPlay
                muted
                loop
                playsInline
                controls
                preload="metadata"
              />
              <figcaption>{t("video.legende")}</figcaption>
            </figure>
          ) : null}
          <div className="wrap cols">
            <div>
              <h2>{t("probleme.titre")}</h2>
              <p className="lede">{t("probleme.chapo")}</p>
              <p className="suite">{t.rich("probleme.corps", { fort })}</p>
              <dl className="versus">
                {(["main", "avec"] as const).map((c) => (
                  <div key={c} className={c}>
                    <dt>{t(`probleme.${c}Titre`)}</dt>
                    <dd>{t(`probleme.${c}Corps`)}</dd>
                  </div>
                ))}
              </dl>
            </div>
            <div className="scenes" aria-hidden="true">
              <figure className="scene">
                <Barre />
                <span className="notch" />
                <Pastille signe={bn.signe} valeur={bn.valeur} w={1.95} />
                <Pastille signe={va.signe} valeur={va.valeur} w={2.15} className="ghost" />
                <span className="tag a">{t("probleme.aLecran", { app: bn.nom })}</span>
                <span className="tag r">{t("probleme.memeEndroit", { app: va.nom })}</span>
                <figcaption>{t("probleme.sans")}</figcaption>
              </figure>
              <figure className="scene">
                <Barre />
                <span className="notch" />
                <Pastille signe={va.signe} valeur={va.valeur} w={2.15} />
                <p className="queue">
                  {apps.map((a, k) => (
                    <span key={a.nom} className={k === 0 ? "on" : undefined}>
                      {k === 0 ? "●" : "○"} {a.nom}
                    </span>
                  ))}
                </p>
                <figcaption>{t("probleme.avec")}</figcaption>
              </figure>
            </div>
          </div>
        </section>

        {/* ------------------------ TROIS FAÇONS ---------------------------
            La même encoche à la même échelle, et le geste dessiné dessus. Trois
            gestes changent d'app, la quatrième carte montre les flèches, qui ne
            sont qu'un repère. */}
        <section id="gesture">
          <div className="wrap">
            <div className="head">
              <h2>{t("commandes.titre")}</h2>
              <p className="lede">{t("commandes.chapo")}</p>
            </div>
            <div className="ways">
              <Facon titre={t("commandes.swipeTitre")} corps={t("commandes.swipeCorps")} pastille={vitrine}>
                <span className="touch">
                  <i />
                  <i />
                </span>
              </Facon>
              <Facon titre={t("commandes.raccourciTitre")} corps={t("commandes.raccourciCorps")} pastille={vitrine}>
                <span className="keys">
                  <kbd>⌃</kbd>
                  <kbd>⌥</kbd>
                  <kbd>⌘</kbd>
                  <kbd>B</kbd>
                </span>
              </Facon>
              <Facon titre={t("commandes.menuTitre")} corps={t("commandes.menuCorps")}>
                <div className="menu">
                  {apps.map((a, k) => (
                    <div key={a.nom} className={k === 1 ? "row hl" : "row"}>
                      <span>{["●", "◐", "○"][k] ?? "○"}</span>
                      <span>{a.nom}</span>
                      <small>{a.libelleVoie}</small>
                    </div>
                  ))}
                </div>
              </Facon>
              <Facon titre={t("commandes.flechesTitre")} corps={t("commandes.flechesCorps")} pastille={vitrine}>
                <span className="arw p">
                  <span>‹</span>
                </span>
                <span className="arw n">
                  <span>›</span>
                </span>
                <svg className="cursor" viewBox="0 0 16 24">
                  <path d="M1 1v19l5-5 3.5 7.5 3-1.4L9 13.6h7z" fill="#fff" stroke="#000" strokeWidth="1.2" />
                </svg>
              </Facon>
            </div>
          </div>
        </section>

        {/* -------------------------- COMPATIBILITÉ -----------------------
            La colonne « Preuve » ne se gomme pas : mesuré et prédit ne se
            mélangent jamais, c'est ce qui rend le tableau crédible. Les lignes
            mesurées d'abord, la voie instantanée avant la relance. */}
        <section className="paper" id="apps">
          <div className="wrap">
            <h2>{t("compatibilite.titre")}</h2>
            <p className="lede">{t("compatibilite.chapo")}</p>
            <p className="nope">{t("compatibilite.pasPourVous")}</p>
            <div className="tbl">
              <table>
                <caption className="sr">{t("compatibilite.legendeTableau")}</caption>
                <thead>
                  <tr>
                    <th scope="col">{t("compatibilite.colonneApp")}</th>
                    <th scope="col">{t("compatibilite.colonneCachee")}</th>
                    <th scope="col">{t("compatibilite.colonnePreuve")}</th>
                    <th scope="col">{t("compatibilite.colonneNote")}</th>
                  </tr>
                </thead>
                <tbody>
                  {LIGNES.map((l) => (
                    <tr key={l.bundleID}>
                      <td>
                        <b>{l.app}</b> <span className="v">{l.version}</span>
                      </td>
                      <td>
                        <span className={l.bascule === "rapide" ? "route i" : "route r"}>
                          {t(l.bascule === "rapide" ? "compatibilite.cacheeOuverte" : "compatibilite.cacheeFermee")}
                        </span>
                      </td>
                      <td>
                        <span className={l.preuve === "mesure" ? "chip m" : "chip p"}>
                          {t(l.preuve === "mesure" ? "compatibilite.preuveMesure" : "compatibilite.preuvePredit")}
                        </span>
                      </td>
                      <td className="v">{t(`compatibilite.lignes.${l.cle}.note`)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="bench">
              {t.rich("compatibilite.banc", {
                date: dateCampagne,
                lien: lienVers(LIENS.matrice),
              })}
            </p>
          </div>
        </section>

        {/* ---------------------------- LE MOTEUR -------------------------
            Deux chiffres mesurés, une garantie. Le détail technique (scan,
            bundle ID, Space privé) vit dans docs/COMPATIBILITE.md, pas ici.
            La frise : la nouvelle app est à l'écran avant que l'ancienne parte. */}
        <section className="dark" id="engine">
          <div className="wrap">
            <h2>{t("moteur.titre")}</h2>
            <div className="cols inv">
              <div>
                <p className="lede">{t("moteur.chapo")}</p>
                <div className="pair">
                  <div>
                    <h3>{t("moteur.refusTitre")}</h3>
                    <p>{t("moteur.refusCorps")}</p>
                  </div>
                  <div>
                    <h3>{t("moteur.detectionTitre")}</h3>
                    <p>{t.rich("moteur.detectionCorps", { lien: lienVers(LIENS.matrice) })}</p>
                  </div>
                </div>
              </div>
              <div className="specs">
                {(["chiffre1", "chiffre3"] as const).map((c) => (
                  <div key={c} className="spec">
                    <b>
                      {t(`moteur.${c}.valeur`)}
                      <small>{t(`moteur.${c}.unite`)}</small>
                    </b>
                    <span>{t(`moteur.${c}.libelle`)}</span>
                    <p>{t(`moteur.${c}.note`)}</p>
                  </div>
                ))}
              </div>
            </div>
            <div className="tl">
              <h3>{t("moteur.friseTitre")}</h3>
              <p>{t("moteur.friseCorps")}</p>
              <div
                className="lanes"
                role="img"
                aria-label={t("moteur.friseLegende", { arrive: bn.nom, part: va.nom })}
              >
                <div className="lane">
                  <span>{t("moteur.arrive", { app: bn.nom })}</span>
                  <div className="track">
                    <span className="seg start">{t("moteur.demarrage")}</span>
                    <span className="seg new">{t("moteur.aLecran")}</span>
                  </div>
                </div>
                <div className="lane">
                  <span>{t("moteur.part", { app: va.nom })}</span>
                  <div className="track">
                    <span className="seg old">{t("moteur.encore")}</span>
                  </div>
                </div>
                <span className="cut">
                  <span>{t("moteur.compte", { app: bn.nom })}</span>
                </span>
              </div>
            </div>
          </div>
        </section>

        {/* -------------------------- INSTALLATION ------------------------
            L'encoche revient, et deux façons d'installer de même poids.
            Gatekeeper reste replié, avec la phrase exacte que macOS affiche :
            « n'a pas pu vérifier » / « cannot verify », jamais « endommagée ». */}
        <section className="install" id="install">
          <div className="wrap">
            <h2>{t("installation.titre")}</h2>
            <p className="lede">{t("installation.chapo")}</p>
            <div className="closer" aria-hidden="true">
              <span className="notch" />
              <Pastille signe={va.signe} valeur={va.valeur} w={2.15} />
            </div>
            <div className="ways2">
              <div className="opt">
                <h3>{t("installation.zipTitre")}</h3>
                <p>{t("installation.zipCorps")}</p>
                <a className="btn" href={LIENS.telechargement}>
                  <Pomme />
                  {t("installation.telecharger")}
                </a>
              </div>
              <div className="opt">
                <h3>{t("installation.brewTitre")}</h3>
                <p>{t("installation.brewCorps")}</p>
                <LigneCommande
                  commande={COMMANDE_BREW}
                  copier={t("installation.copier")}
                  copie={t("installation.copie")}
                  echec={t("installation.echecCopie")}
                />
              </div>
            </div>
            {/* La permission la plus intrusive de macOS, demandée par une app
                non notarisée : la réponse se lit à côté du bouton, pas en bas. */}
            <div className="trust">
              {(["acces", "sortie", "desinstaller"] as const).map((c) => (
                <div key={c}>
                  <h3>{t(`installation.${c}Titre`)}</h3>
                  <p>{t.rich(`installation.${c}Corps`, { lien: lienVers(LIENS.depot), code })}</p>
                </div>
              ))}
            </div>
            <ul className="need">
              <li>{t("installation.requis1")}</li>
              <li>{t("installation.requis2")}</li>
              <li>{t("installation.requis3")}</li>
            </ul>
            <details>
              <summary>{t("installation.gatekeeperQuestion")}</summary>
              <p>{t("installation.gatekeeper1")}</p>
              <p>{t("installation.gatekeeper2")}</p>
              <p>{t("installation.gatekeeper3")}</p>
            </details>
          </div>
        </section>
      </main>

      <footer>
        <div className="wrap">
          <span>{t("chrome.piedLigne")}</span>
          <nav aria-label={t("chrome.piedNav")}>
            <a href={LIENS.depot}>{t("chrome.piedGithub")}</a>
            <a href={LIENS.versions}>{t("chrome.piedVersions")}</a>
            <a href={LIENS.matrice}>{t("chrome.piedCompat")}</a>
            <a href={`../${autre}/`} lang={autre} hrefLang={autre}>
              {NOMS_LANGUES[autre]}
            </a>
          </nav>
        </div>
      </footer>
    </>
  );
}

/** Mesuré avant prédit, puis instantané avant relance. Le tri est stable : à
    égalité, l'ordre du JSON tient. */
const LIGNES: readonly LigneCompatibilite[] = [...COMPATIBILITE].sort(
  (a, b) =>
    Number(a.preuve === "predit") - Number(b.preuve === "predit") ||
    Number(a.bascule === "relance") - Number(b.bascule === "relance"),
);

/** Les entrées de la barre des menus : l'ancre de la section, et sa clé. */
const NAV = [
  ["#problem", "pourquoi"],
  ["#gesture", "changer"],
  ["#apps", "apps"],
  ["#engine", "fonctionnement"],
  ["#install", "installer"],
] as const;

const LIBELLE_BASCULE = {
  rapide: "basculeRapide",
  relance: "basculeRelance",
} as const;

/** La barre des menus d'une scène. Finder et 9:41 ne se traduisent pas. */
function Barre() {
  return (
    <div className="strip">
      <span>Finder</span>
      <span>9:41</span>
    </div>
  );
}

/** Une carte des façons de changer d'app : la scène avec son geste, un titre, une phrase. */
function Facon({
  titre,
  corps,
  pastille,
  children,
}: {
  titre: string;
  corps: string;
  pastille?: { signe: AppBureau["signe"]; valeur: string };
  children: ReactNode;
}) {
  return (
    <article className="way">
      <figure className="scene" aria-hidden="true">
        <Barre />
        <span className="notch" />
        {pastille ? <Pastille signe={pastille.signe} valeur={pastille.valeur} w={2.15} /> : null}
        {children}
      </figure>
      <h3>{titre}</h3>
      <p>{corps}</p>
    </article>
  );
}
