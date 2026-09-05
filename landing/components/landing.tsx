import type { ReactNode } from "react";
import { useTranslations } from "next-intl";
import { COMPATIBILITE } from "@/content/compatibilite";
import { COMMANDE_BREW, COMMANDE_VERIF, LIENS } from "@/content/liens";
import { ApercuVivant } from "./apercu";
import { BoutonAncre, LigneCommande } from "./actions";
import * as m from "./mise-en-page";
import { SelecteurLangue } from "./selecteur-langue";

/* Les balises que le texte traduit a le droit de porter. Elles restent dans le
   code : une traduction choisit où le renfort tombe dans sa phrase, pas de quoi
   il est fait. Le lien, lui, prend son URL ici — content/liens.ts est la seule
   source, dans toutes les langues. */
const fort = (c: ReactNode) => <strong>{c}</strong>;
const code = (c: ReactNode) => <code className="font-mono text-sm">{c}</code>;
const lienVers = (href: string) => (c: ReactNode) => <a href={href}>{c}</a>;

/**
 * La page entière. Elle ne connaît pas la langue : `useTranslations` la lit
 * dans le segment [locale] et rend le dictionnaire correspondant — la version
 * anglaise est le même arbre avec d'autres chaînes, pas une seconde copie du
 * balisage.
 *
 * L'ordre des sections répond aux questions dans l'ordre où on se les pose :
 * qu'est-ce que ça fait (on le voit, on y joue), pourquoi j'en ai besoin,
 * comment je m'en sers, qu'est-ce qui se passe dessous, est-ce que ça marche
 * chez moi, qu'est-ce qu'il me faut, comment je l'installe, et le reste.
 */
export function Landing() {
  const t = useTranslations();

  /* L'aperçu est un composant client : il reçoit des chaînes déjà résolues,
     donc aucun dictionnaire ne part au navigateur. */
  const demo = {
    noms: [t("demo.nom1"), t("demo.nom2"), t("demo.nom3")] as [
      string,
      string,
      string,
    ],
    agents: t("demo.agents"),
    duree: t("demo.duree"),
    jour: t("demo.jour"),
    heure: t("demo.heure"),
  };
  const libelles = {
    invite: t("apercu.invite"),
    enScene: t("apercu.enScene"),
    debranche: t("apercu.debranche"),
    bouncerActif: t("apercu.bouncerActif"),
    precedente: t("apercu.precedente"),
    suivante: t("apercu.suivante"),
    choisir: t("apercu.choisir"),
    raccourci: t("apercu.raccourci"),
  };

  return (
    <>
      <a
        href="#contenu"
        className="absolute top-0 left-[-9999px] z-20 rounded-br-lg border-0 bg-encre px-[18px] py-[10px] text-white focus:left-0"
      >
        {t("chrome.evitement")}
      </a>

      <header className="border-b border-filet">
        <div className={`${m.enveloppe} flex h-[58px] items-center justify-between`}>
          <span className="text-[1.0625rem] font-semibold tracking-[-.015em]">
            Bouncer
          </span>
          <span className="flex items-center gap-[22px]">
            <SelecteurLangue />
            <a
              href={LIENS.depot}
              className="border-0 text-[.9375rem] text-gris hover:text-encre"
            >
              {t("chrome.codeSource")}
            </a>
          </span>
        </div>
      </header>

      <main id="contenu" tabIndex={-1}>
        {/* ---------------------------- HÉROS ----------------------------
            Le titre, puis tout de suite le produit qui marche. On ne demande
            pas de lire une promesse : on donne l'app à toucher. */}
        <section className="scroll-mt-6 pt-haut-heros pb-pas">
          <div className={m.enveloppe}>
            <h1 className="mb-[.32em] text-balance text-center text-heros font-semibold leading-[1.03] tracking-heros">
              {t("heros.titreLigne1")}
              <br />
              {t("heros.titreLigne2")}
            </h1>
            <p className={`${m.chapo} max-w-[33rem]`}>{t("heros.chapo")}</p>
            <div className="mt-[34px] flex flex-wrap items-center justify-center gap-[14px]">
              <BoutonAncre vers="#installer">{t("heros.installer")}</BoutonAncre>
              <a
                href="#compatibilite"
                className="border-b-filet text-[.9375rem] text-gris"
              >
                {t("heros.voirCompatibles")}
              </a>
            </div>

            <ApercuVivant demo={demo} l={libelles} />
          </div>
        </section>

        {/* --------------------------- LE PROBLÈME ------------------------ */}
        <section className="scroll-mt-6 py-pas">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("probleme.titre")}</h2>
            <div className={`${m.bloc} ${m.corps}`}>
              <p>{t("probleme.para1")}</p>
              <p>{t.rich("probleme.para2", { fort })}</p>
            </div>
          </div>
        </section>

        {/* --------------------------- LES COMMANDES ----------------------
            Une carte par voie de commande. Chacune porte son propre signe,
            emprunté au produit : le trackpad, les deux chevrons du boîtier
            caméra, les touches du raccourci, les pastilles du menu. */}
        <section className="scroll-mt-6 py-pas" id="commandes">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("commandes.titre")}</h2>
            <p className={m.chapo}>{t("commandes.chapo")}</p>

            <div className="mt-12 grid gap-[18px] sm:grid-cols-2">
              <Carte titre={t("commandes.swipeTitre")} signe={<SigneSwipe />}>
                {t("commandes.swipeCorps")}
              </Carte>
              <Carte titre={t("commandes.flechesTitre")} signe={<SigneFleches />}>
                {t("commandes.flechesCorps")}
              </Carte>
              <Carte
                titre={t("commandes.raccourciTitre")}
                signe={
                  <span className="flex items-center gap-[5px]">
                    <kbd>⌃</kbd>
                    <kbd>⌥</kbd>
                    <kbd>⌘</kbd>
                    <kbd>B</kbd>
                  </span>
                }
              >
                {t("commandes.raccourciCorps")}
              </Carte>
              <Carte
                titre={t("commandes.menuTitre")}
                signe={
                  <span className="flex flex-col gap-[3px] text-[.8125rem] text-gris">
                    <span>
                      <b className="text-encre">●</b> {t("commandes.menuActive")}
                    </span>
                    <span>○ {t("commandes.menuAttente")}</span>
                    <span>◐ {t("commandes.menuEnCours")}</span>
                  </span>
                }
              >
                {t("commandes.menuCorps")}
              </Carte>
            </div>
          </div>
        </section>

        {/* ---------------------------- LE MOTEUR -------------------------
            Les trois chiffres mesurés, puis les deux garanties qui décident
            si on ose installer : ce que Bouncer promet, et ce qu'il refuse. */}
        <section className="scroll-mt-6 py-pas" id="moteur">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("moteur.titre")}</h2>
            <p className={m.chapo}>{t("moteur.chapo")}</p>

            <div className="mt-12 grid gap-[18px] sm:grid-cols-3">
              {([1, 2, 3] as const).map((n) => (
                <div key={n} className={`${m.carte} px-6 py-[26px]`}>
                  <p className="mb-[.2em] text-[2rem] font-semibold tabular-nums tracking-[-.03em] text-encre">
                    {t(`moteur.chiffre${n}`)}
                  </p>
                  <p className="mb-[.7em] text-[.9375rem] font-medium text-encre">
                    {t(`moteur.libelle${n}`)}
                  </p>
                  <p className="mb-0 text-[.875rem] text-gris">
                    {t(`moteur.note${n}`)}
                  </p>
                </div>
              ))}
            </div>

            <div className={`${m.bloc} ${m.corps} mt-14`}>
              <h3 className={m.sousTitre}>{t("moteur.garantieTitre")}</h3>
              <p>{t.rich("moteur.garantieCorps", { fort })}</p>
              <h3 className={`${m.sousTitre} mt-[1.6em]`}>
                {t("moteur.refusTitre")}
              </h3>
              <p>{t("moteur.refusCorps")}</p>
            </div>
          </div>
        </section>

        {/* -------------------------- COMPATIBILITÉ -----------------------
            La colonne dit la VOIE de bascule, pas un oui/non : toute app que
            Bouncer voit sous l'encoche bascule, la question est à quelle
            vitesse. Ce qui reste honnête, c'est mesuré contre prédit, et la
            colonne le porte ligne par ligne. */}
        <section className="scroll-mt-6 py-pas" id="compatibilite">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("compatibilite.titre")}</h2>
            <p className={m.chapo}>{t("compatibilite.chapo")}</p>

            <div className="mt-11 w-full overflow-x-auto">
              <table className="w-full min-w-[600px] border-collapse text-[.9375rem] tabular-nums">
                <caption className="sr-only">
                  {t("compatibilite.legendeTableau")}
                </caption>
                <thead>
                  <tr>
                    {(["colonne1", "colonne2", "colonne3", "colonne4"] as const).map(
                      (c) => (
                        <th
                          key={c}
                          scope="col"
                          className="border-b border-filet pt-[15px] pr-4 pb-[11px] text-left align-top text-[.875rem] font-semibold text-gris"
                        >
                          {t(`compatibilite.${c}`)}
                        </th>
                      ),
                    )}
                  </tr>
                </thead>
                <tbody>
                  {COMPATIBILITE.map((l) => (
                    <tr key={l.bundleID}>
                      <td className={`${cellule} font-semibold`}>{l.app}</td>
                      <td className={cellule}>{l.version}</td>
                      <td className={cellule}>
                        <span className={COULEUR_BASCULE[l.bascule]}>
                          {t(`compatibilite.${LIBELLE_BASCULE[l.bascule]}`)}
                        </span>
                        <span className="mt-[3px] block max-w-[34rem] text-[.875rem] text-gris">
                          {t(`compatibilite.lignes.${l.cle}.note`)}
                        </span>
                      </td>
                      <td className={`${cellule} whitespace-nowrap`}>
                        <span
                          className={
                            l.preuve === "mesure"
                              ? "rounded-full bg-encre px-[9px] py-[3px] text-[.75rem] font-medium text-white"
                              : "rounded-full border border-filet px-[9px] py-[3px] text-[.75rem] text-gris"
                          }
                        >
                          {t(
                            l.preuve === "mesure"
                              ? "compatibilite.preuveMesure"
                              : "compatibilite.preuvePredit",
                          )}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <p className="mx-auto mt-[18px] max-w-[46rem] text-center text-[.875rem] text-gris">
              {t("compatibilite.banc")}
            </p>

            <div className={`${m.bloc} ${m.corps} mt-12`}>
              <p>{t("compatibilite.para1")}</p>
              <p>{t.rich("compatibilite.para2", { fort })}</p>
              <p>
                {t.rich("compatibilite.para3", {
                  lien: lienVers(LIENS.matrice),
                })}
              </p>
            </div>

            <div className={`${m.bloc} mt-14`}>
              <h3 className={m.sousTitre}>{t("compatibilite.verifierTitre")}</h3>
            </div>
            <LigneCommande
              commande={COMMANDE_VERIF}
              copier={t("installation.copier")}
              copie={t("installation.copie")}
              echec={t("installation.echecCopie")}
            />
            <div className={`${m.bloc} ${m.corps} mt-[22px] text-center`}>
              <p>{t("compatibilite.verifierCorps")}</p>
            </div>
          </div>
        </section>

        {/* --------------------------- LES PRÉREQUIS ---------------------- */}
        <section className="scroll-mt-6 py-pas" id="prerequis">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("prerequis.titre")}</h2>
            <p className={m.chapo}>{t("prerequis.chapo")}</p>

            <div className="mt-12 grid gap-[18px] sm:grid-cols-2">
              {([1, 2, 3, 4] as const).map((n) => (
                <Carte key={n} titre={t(`prerequis.item${n}Titre`)}>
                  {t(`prerequis.item${n}Corps`)}
                </Carte>
              ))}
            </div>
          </div>
        </section>

        {/* -------------------------- INSTALLATION ------------------------ */}
        <section className="scroll-mt-6 py-pas" id="installer">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("installation.titre")}</h2>
            <p className={m.chapo}>{t("installation.chapo")}</p>

            <LigneCommande
              commande={COMMANDE_BREW}
              copier={t("installation.copier")}
              copie={t("installation.copie")}
              echec={t("installation.echecCopie")}
            />
            <div className={`${m.bloc} ${m.corps} mt-[22px] text-center`}>
              <p>{t("installation.sousLaCommande")}</p>
            </div>

            <div className={`${m.bloc} mt-14`}>
              <h3 className={m.sousTitre}>{t("installation.sansHomebrew")}</h3>
            </div>
            <ol className={m.etapes}>
              <li>
                {t.rich("installation.archive1", {
                  code,
                  lien: lienVers(LIENS.versions),
                })}
              </li>
              <li>{t("installation.archive2")}</li>
              <li>{t("installation.archive3")}</li>
            </ol>

            {/* Point d'honnêteté nº 1 : Gatekeeper. L'app n'est PAS notarisée,
                macOS dira « n'a pas pu vérifier » — pas « endommagée ». */}
            <div className={`${m.bloc} ${m.carte} mt-[34px] px-6 py-[22px] [&>p:last-child]:mb-0`}>
              <p className="font-medium text-encre">
                {t("installation.citationGatekeeper")}
              </p>
              <p className="text-gris">{t("installation.expliqueGatekeeper")}</p>
            </div>

            <div className={`${m.bloc} ${m.corps} mt-[34px]`}>
              <p>{t("installation.ouvrirQuandMeme")}</p>
            </div>
            <ol className={m.etapes}>
              <li>{t("installation.gatekeeper1")}</li>
              <li>{t("installation.gatekeeper2")}</li>
              <li>{t("installation.gatekeeper3")}</li>
              <li>{t("installation.gatekeeper4")}</li>
            </ol>
            <div className={`${m.bloc} ${m.corps} mt-[22px]`}>
              <p>{t("installation.apres1")}</p>
              <p>{t("installation.apres2")}</p>
            </div>
          </div>
        </section>

        {/* ------------------------------- FAQ ---------------------------- */}
        <section className="scroll-mt-6 py-pas" id="questions">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("faq.titre")}</h2>

            <dl className="mx-auto mt-12 grid max-w-[62rem] gap-x-[42px] gap-y-9 sm:grid-cols-2">
              {([1, 2, 3, 4, 5, 6] as const).map((n) => (
                <div key={n}>
                  <dt className="mb-[.45em] font-semibold text-encre">
                    {t(`faq.q${n}`)}
                  </dt>
                  <dd className="m-0 text-gris">
                    {t.rich(`faq.r${n}`, { code })}
                  </dd>
                </div>
              ))}
            </dl>
          </div>
        </section>

        {/* ------------------------------ LA FIN --------------------------
            La page se termine sur l'action, pas sur la dernière réponse de
            la FAQ. Le bouton est le même que celui du héros : il descend à
            la section d'installation, où la commande est déjà copiable. */}
        <section className="scroll-mt-6 border-t border-filet py-pas">
          <div className={`${m.enveloppe} text-center`}>
            <h2 className="mx-auto mb-[.4em] max-w-[24ch] text-balance text-[2rem] font-semibold tracking-[-.03em] text-encre">
              {t("fin.titre")}
            </h2>
            <p className="mx-auto mb-8 max-w-[32rem] text-gris">
              {t("fin.corps")}
            </p>
            <BoutonAncre vers="#installer">{t("fin.action")}</BoutonAncre>
          </div>
        </section>
      </main>

      <footer className="border-t border-filet pt-[38px] pb-[52px] text-[.875rem] text-gris [&_a]:border-b-filet [&_a]:text-gris hover:[&_a]:text-encre">
        <div className={`${m.enveloppe} flex flex-wrap justify-between gap-[18px]`}>
          <span>{t("chrome.piedLigne")}</span>
          <span className="flex gap-[22px]">
            <a href={LIENS.depot}>{t("chrome.piedGithub")}</a>
            <a href={LIENS.versions}>{t("chrome.piedVersions")}</a>
          </span>
        </div>
      </footer>
    </>
  );
}

const cellule =
  "border-b border-filet pt-[15px] pr-4 pb-[15px] text-left align-top";

/* Les trois voies de bascule, et ce qu'elles valent à l'œil. « Instantanée »
   est la seule qui prend l'accent : c'est le cas nominal. « Pas encore vue »
   reste en gris — c'est un manque connu, chiffré et corrigeable, pas un échec
   de l'app ni de Bouncer. */
const LIBELLE_BASCULE = {
  rapide: "basculeRapide",
  relance: "basculeRelance",
  invisible: "basculeInvisible",
} as const;

const COULEUR_BASCULE = {
  rapide: "font-semibold text-accent",
  relance: "font-semibold text-encre",
  invisible: "text-gris",
} as const;

/** Une carte de la grille : un signe optionnel, un titre, une phrase. C'est la
    seule forme répétée de la page en dehors du texte courant. */
function Carte({
  titre,
  signe,
  children,
}: {
  titre: string;
  signe?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className={`${m.carte} px-6 py-[26px]`}>
      {signe ? (
        <div className="mb-[18px] flex h-[58px] items-center">{signe}</div>
      ) : null}
      <h3 className="mb-[.5em] text-[1.0625rem] font-semibold tracking-[-.015em] text-encre">
        {titre}
      </h3>
      <p className="mb-0 text-[.9375rem] text-gris">{children}</p>
    </div>
  );
}

/** Un trackpad et le va-et-vient qu'on y fait. */
function SigneSwipe() {
  return (
    <svg viewBox="0 0 52 34" width="52" height="34" fill="none" aria-hidden="true">
      <rect
        x="0.8"
        y="0.8"
        width="50.4"
        height="32.4"
        rx="5"
        stroke="var(--color-filet)"
        strokeWidth="1.6"
      />
      <path
        d="M13 17h26"
        stroke="var(--color-encre)"
        strokeWidth="1.6"
        strokeLinecap="round"
      />
      <path
        d="M17 12.5 12.2 17l4.8 4.5M35 12.5l4.8 4.5-4.8 4.5"
        stroke="var(--color-encre)"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

/** Le boîtier caméra, et les deux chevrons de part et d'autre. */
function SigneFleches() {
  return (
    <span className="flex items-center gap-[10px] text-encre">
      <svg viewBox="0 0 9 14" width="9" height="14" fill="none" aria-hidden="true">
        <path
          d="M7.5 1 1.5 7l6 6"
          stroke="currentColor"
          strokeWidth="1.7"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
      <span className="h-[18px] w-[54px] rounded-b-[7px] bg-noir" />
      <svg viewBox="0 0 9 14" width="9" height="14" fill="none" aria-hidden="true">
        <path
          d="M1.5 1l6 6-6 6"
          stroke="currentColor"
          strokeWidth="1.7"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </span>
  );
}
