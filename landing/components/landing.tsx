import type { ReactNode } from "react";
import { useTranslations } from "next-intl";
import { COMPATIBILITE } from "@/content/compatibilite";
import { LIENS } from "@/content/liens";
import { BoutonAncre, LigneCommande } from "./actions";
import * as m from "./mise-en-page";
import { SceneFleches, SceneGeste, SceneHeros } from "./scenes";
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
 * dans le segment [locale] et rend le dictionnaire correspondant. C'est tout
 * l'objet du portage — la version anglaise est le même arbre avec d'autres
 * chaînes, pas une seconde copie du balisage.
 */
export function Landing() {
  const t = useTranslations();

  /* Les panneaux de démo sont rendus par des composants client : ils reçoivent
     des chaînes déjà résolues, donc aucun dictionnaire ne part au navigateur. */
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
        {/* ---------------------------- HÉROS ---------------------------- */}
        <section className="heros scroll-mt-6 pt-haut-heros pb-pas">
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

            <SceneHeros
              demo={demo}
              avant={t("heros.legendeAvant")}
              apres={t("heros.legendeApres")}
            />
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

        {/* ---------------------------- LE GESTE -------------------------- */}
        <section className="geste scroll-mt-6 pt-pas pb-0" id="geste">
          <SceneGeste
            demo={demo}
            titre={t("geste.titre")}
            sousTitre={t("geste.chapo")}
          />
        </section>

        {/* --------------------------- LES FLÈCHES ------------------------ */}
        <section className="fleches scroll-mt-6 py-pas">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("fleches.titre")}</h2>
            <p className={m.chapo}>{t("fleches.chapo")}</p>

            <SceneFleches
              demo={demo}
              precedente={t("fleches.precedente")}
              suivante={t("fleches.suivante")}
            />

            <div className={`${m.bloc} ${m.corps} mt-[52px]`}>
              <p>{t("fleches.corps")}</p>
            </div>
          </div>
        </section>

        {/* -------------------------- COMPATIBILITÉ ----------------------- */}
        <section className="scroll-mt-6 py-pas" id="compatibilite">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("compatibilite.titre")}</h2>
            <p className={m.chapo}>{t("compatibilite.chapo")}</p>

            <div className="mt-11 w-full overflow-x-auto">
              <table className="w-full min-w-[520px] border-collapse text-[.9375rem] tabular-nums">
                <caption className="sr-only">
                  {t("compatibilite.legendeTableau")}
                </caption>
                <thead>
                  <tr>
                    {(["colonne1", "colonne2", "colonne3"] as const).map((c) => (
                      <th
                        key={c}
                        scope="col"
                        className="border-b border-filet pt-[15px] pr-4 pb-[11px] text-left align-top text-[.875rem] font-semibold text-gris"
                      >
                        {t(`compatibilite.${c}`)}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {COMPATIBILITE.map((l) => (
                    <tr key={l.app}>
                      <td className={`${cellule} font-semibold`}>{l.app}</td>
                      <td className={cellule}>{l.version}</td>
                      <td className={cellule}>
                        <span
                          className={
                            l.verdict === "oui"
                              ? "font-semibold text-accent"
                              : "text-gris"
                          }
                        >
                          {t(`compatibilite.lignes.${l.cle}.libelle`)}
                        </span>
                        <span className="mt-[3px] block text-[.875rem] text-gris">
                          {t(`compatibilite.lignes.${l.cle}.note`)}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className={`${m.bloc} ${m.corps} mt-11`}>
              <p>{t("compatibilite.para1")}</p>
              <p>{t("compatibilite.para2")}</p>
              <p>
                {t.rich("compatibilite.para3", {
                  fort,
                  lien: lienVers(LIENS.readmeResistance),
                })}
              </p>
            </div>
          </div>
        </section>

        {/* -------------------------- INSTALLATION ------------------------ */}
        <section className="scroll-mt-6 py-pas" id="installer">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{t("installation.titre")}</h2>
            <p className={m.chapo}>{t("installation.chapo")}</p>

            <LigneCommande
              copier={t("installation.copier")}
              copie={t("installation.copie")}
              echec={t("installation.echecCopie")}
            />
            <div className={`${m.bloc} ${m.corps} mt-[22px] text-center`}>
              <p>{t("installation.sousLaCommande")}</p>
            </div>

            <div className={`${m.bloc} mt-14`}>
              <h3 className="mb-[.8em] text-[1.25rem] font-semibold tracking-[-.02em] text-encre">
                {t("installation.sansHomebrew")}
              </h3>
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
