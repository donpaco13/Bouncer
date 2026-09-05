"use client";

import { useState } from "react";
import { useMouvementReduit } from "./mouvement";

/** Le bouton plein du héros : il descend jusqu'à la section d'installation. */
export function BoutonAncre({
  vers,
  children,
}: {
  vers: string;
  children: string;
}) {
  const reduit = useMouvementReduit();
  return (
    <button
      type="button"
      className="cursor-pointer rounded-full border-0 bg-encre px-6 py-3 text-[.9375rem] font-medium text-white transition-colors duration-200 ease-courbe hover:bg-black"
      onClick={() =>
        document.querySelector(vers)?.scrollIntoView({
          behavior: reduit ? "auto" : "smooth",
          block: "start",
        })
      }
    >
      {children}
    </button>
  );
}

/** Une ligne de commande et son bouton de copie. La commande arrive en prop :
    la page en affiche deux — l'installation et la vérification — et elles
    n'ont aucune raison d'être deux composants. */
export function LigneCommande({
  commande,
  copier,
  copie,
  echec,
}: {
  commande: string;
  copier: string;
  copie: string;
  echec: string;
}) {
  const [libelle, setLibelle] = useState(copier);

  const surClic = () =>
    navigator.clipboard.writeText(commande).then(
      () => {
        setLibelle(copie);
        setTimeout(() => setLibelle(copier), 1800);
      },
      () => setLibelle(echec),
    );

  return (
    <div className="mx-auto mt-7 flex max-w-[38rem] items-center justify-between gap-[14px] rounded-xl border border-filet bg-fond-carte py-[14px] pr-[14px] pl-[18px]">
      <code className="overflow-x-auto font-mono text-[.875rem] whitespace-nowrap">
        {commande}
      </code>
      <button
        type="button"
        onClick={surClic}
        className="flex-none cursor-pointer rounded-full border border-filet bg-white px-[14px] py-[6px] text-[.8125rem] text-gris hover:border-[#D4D4D8] hover:text-encre"
      >
        {libelle}
      </button>
    </div>
  );
}
