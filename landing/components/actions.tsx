"use client";

import { useState } from "react";

type Libelles = { copier: string; copie: string; echec: string };

/** Un bouton qui copie un texte et le dit, puis revient à son libellé. */
export function BoutonCopie({ texte, copier, copie, echec, className }: Libelles & { texte: string; className?: string }) {
  const [libelle, setLibelle] = useState(copier);

  /* Hors contexte sûr, `navigator.clipboard` n'existe pas : passer par une
     promesse fait tomber cette erreur-là dans le même échec que les autres. */
  const surClic = () =>
    Promise.resolve()
      .then(() => navigator.clipboard.writeText(texte))
      .then(
        () => {
          setLibelle(copie);
          setTimeout(() => setLibelle(copier), 1800);
        },
        () => setLibelle(echec),
      );

  return (
    <button type="button" className={className} onClick={surClic}>
      {libelle}
    </button>
  );
}

/** Une ligne de commande et son bouton de copie. */
export function LigneCommande({ commande, ...l }: Libelles & { commande: string }) {
  return (
    <div className="cmd">
      <code>{commande}</code>
      <BoutonCopie texte={commande} {...l} />
    </div>
  );
}
