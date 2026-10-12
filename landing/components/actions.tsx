"use client";

import { useState } from "react";

/** Une ligne de commande et son bouton de copie. */
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
    <div className="cmd">
      <code>{commande}</code>
      <button type="button" onClick={surClic}>
        {libelle}
      </button>
    </div>
  );
}
