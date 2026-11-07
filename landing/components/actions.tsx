"use client";

import { useState } from "react";

type Libelles = { copier: string; copie: string; echec: string };

/**
 * Un bouton qui copie un texte et le dit, puis revient à son libellé.
 *
 * Avec `partage`, il ouvre d'abord la feuille de partage du système (AirDrop
 * vers le Mac, Messages, Mail) et ne copie que si elle n'existe pas ou échoue.
 * `navigator.share` est appelé dans le clic lui-même : Safari refuse la feuille
 * hors d'un geste du visiteur. Fermer la feuille rejette avec `AbortError` :
 * le visiteur a changé d'avis, on ne copie pas dans son dos.
 */
export function BoutonCopie({
  texte,
  copier,
  copie,
  echec,
  partage = false,
  className,
}: Libelles & { texte: string; partage?: boolean; className?: string }) {
  const [libelle, setLibelle] = useState(copier);

  /* Hors contexte sûr, `navigator.clipboard` n'existe pas : passer par une
     promesse fait tomber cette erreur-là dans le même échec que les autres. */
  const copierTexte = () =>
    Promise.resolve()
      .then(() => navigator.clipboard.writeText(texte))
      .then(
        () => {
          setLibelle(copie);
          setTimeout(() => setLibelle(copier), 1800);
        },
        () => setLibelle(echec),
      );

  const surClic = () => {
    if (partage && typeof navigator.share === "function") {
      navigator.share({ title: document.title, url: texte }).catch((e: unknown) => {
        if (!(e instanceof DOMException && e.name === "AbortError")) copierTexte();
      });
      return;
    }
    copierTexte();
  };

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
