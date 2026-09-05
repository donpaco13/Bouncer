import type { Dictionary } from "@/content/dictionary";
import { LIENS } from "@/content/liens";
import { BoutonAncre, LigneCommande } from "./actions";
import * as m from "./mise-en-page";
import { SceneFleches, SceneGeste, SceneHeros } from "./scenes";

/**
 * La page entière. Elle ne connaît pas la langue : elle reçoit un dictionnaire
 * et le rend. C'est tout l'objet du portage — la version anglaise sera le même
 * arbre avec un autre dictionnaire, pas une seconde copie du balisage.
 */
export function Landing({ d }: { d: Dictionary }) {
  return (
    <>
      <a
        href="#contenu"
        className="absolute top-0 left-[-9999px] z-20 rounded-br-lg border-0 bg-encre px-[18px] py-[10px] text-white focus:left-0"
      >
        {d.chrome.evitement}
      </a>

      <header className="border-b border-filet">
        <div className={`${m.enveloppe} flex h-[58px] items-center justify-between`}>
          <span className="text-[1.0625rem] font-semibold tracking-[-.015em]">
            Bouncer
          </span>
          <a
            href={LIENS.depot}
            className="border-0 text-[.9375rem] text-gris hover:text-encre"
          >
            {d.chrome.codeSource}
          </a>
        </div>
      </header>

      <main id="contenu" tabIndex={-1}>
        {/* ---------------------------- HÉROS ---------------------------- */}
        <section className="heros scroll-mt-6 pt-haut-heros pb-pas">
          <div className={m.enveloppe}>
            <h1 className="mb-[.32em] text-balance text-center text-heros font-semibold leading-[1.03] tracking-heros">
              {d.heros.titre}
            </h1>
            <p className={`${m.chapo} max-w-[33rem]`}>{d.heros.chapo}</p>
            <div className="mt-[34px] flex flex-wrap items-center justify-center gap-[14px]">
              <BoutonAncre vers="#installer">{d.heros.installer}</BoutonAncre>
              <a
                href="#compatibilite"
                className="border-b-filet text-[.9375rem] text-gris"
              >
                {d.heros.voirCompatibles}
              </a>
            </div>

            <SceneHeros
              demo={d.demo}
              avant={d.heros.legendeAvant}
              apres={d.heros.legendeApres}
            />
          </div>
        </section>

        {/* --------------------------- LE PROBLÈME ------------------------ */}
        <section className="scroll-mt-6 py-pas">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{d.probleme.titre}</h2>
            <div className={`${m.bloc} ${m.corps}`}>{d.probleme.corps}</div>
          </div>
        </section>

        {/* ---------------------------- LE GESTE -------------------------- */}
        <section className="geste scroll-mt-6 pt-pas pb-0" id="geste">
          <SceneGeste
            demo={d.demo}
            titre={d.geste.titre}
            sousTitre={d.geste.chapo}
          />
        </section>

        {/* --------------------------- LES FLÈCHES ------------------------ */}
        <section className="fleches scroll-mt-6 py-pas">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{d.fleches.titre}</h2>
            <p className={m.chapo}>{d.fleches.chapo}</p>

            <SceneFleches
              demo={d.demo}
              precedente={d.fleches.precedente}
              suivante={d.fleches.suivante}
            />

            <div className={`${m.bloc} ${m.corps} mt-[52px]`}>
              {d.fleches.corps}
            </div>
          </div>
        </section>

        {/* -------------------------- COMPATIBILITÉ ----------------------- */}
        <section className="scroll-mt-6 py-pas" id="compatibilite">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{d.compatibilite.titre}</h2>
            <p className={m.chapo}>{d.compatibilite.chapo}</p>

            <div className="mt-11 w-full overflow-x-auto">
              <table className="w-full min-w-[520px] border-collapse text-[.9375rem] tabular-nums">
                <caption className="sr-only">
                  {d.compatibilite.legendeTableau}
                </caption>
                <thead>
                  <tr>
                    {d.compatibilite.colonnes.map((c) => (
                      <th
                        key={c}
                        scope="col"
                        className="border-b border-filet pt-[15px] pr-4 pb-[11px] text-left align-top text-[.875rem] font-semibold text-gris"
                      >
                        {c}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {d.compatibilite.lignes.map((l) => (
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
                          {l.libelle}
                        </span>
                        <span className="mt-[3px] block text-[.875rem] text-gris">
                          {l.note}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className={`${m.bloc} ${m.corps} mt-11`}>
              {d.compatibilite.corps}
            </div>
          </div>
        </section>

        {/* -------------------------- INSTALLATION ------------------------ */}
        <section className="scroll-mt-6 py-pas" id="installer">
          <div className={m.enveloppe}>
            <h2 className={m.titre}>{d.installation.titre}</h2>
            <p className={m.chapo}>{d.installation.chapo}</p>

            <LigneCommande
              copier={d.installation.copier}
              copie={d.installation.copie}
              echec={d.installation.echecCopie}
            />
            <div className={`${m.bloc} ${m.corps} mt-[22px] text-center`}>
              <p>{d.installation.sousLaCommande}</p>
            </div>

            <div className={`${m.bloc} mt-14`}>
              <h3 className="mb-[.8em] text-[1.25rem] font-semibold tracking-[-.02em] text-encre">
                {d.installation.sansHomebrew}
              </h3>
            </div>
            <ol className={m.etapes}>
              {d.installation.etapesArchive.map((e, i) => (
                <li key={i}>{e}</li>
              ))}
            </ol>

            {/* Point d'honnêteté nº 1 : Gatekeeper. L'app n'est PAS notarisée,
                macOS dira « n'a pas pu vérifier » — pas « endommagée ». */}
            <div className={`${m.bloc} ${m.carte} mt-[34px] px-6 py-[22px] [&>p:last-child]:mb-0`}>
              <p className="font-medium text-encre">
                {d.installation.citationGatekeeper}
              </p>
              <p className="text-gris">{d.installation.expliqueGatekeeper}</p>
            </div>

            <div className={`${m.bloc} ${m.corps} mt-[34px]`}>
              <p>{d.installation.ouvrirQuandMeme}</p>
            </div>
            <ol className={m.etapes}>
              {d.installation.etapesGatekeeper.map((e, i) => (
                <li key={i}>{e}</li>
              ))}
            </ol>
            <div className={`${m.bloc} ${m.corps} mt-[22px]`}>
              {d.installation.apresGatekeeper}
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-filet pt-[38px] pb-[52px] text-[.875rem] text-gris [&_a]:border-b-filet [&_a]:text-gris hover:[&_a]:text-encre">
        <div className={`${m.enveloppe} flex flex-wrap justify-between gap-[18px]`}>
          <span>{d.chrome.piedLigne}</span>
          <span className="flex gap-[22px]">
            <a href={LIENS.depot}>{d.chrome.piedGithub}</a>
            <a href={LIENS.versions}>{d.chrome.piedVersions}</a>
          </span>
        </div>
      </footer>
    </>
  );
}

const cellule =
  "border-b border-filet pt-[15px] pr-4 pb-[15px] text-left align-top";
