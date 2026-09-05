"use client";

import { useEffect, useState } from "react";

/**
 * `prefers-reduced-motion`. Rendu serveur : on part de `false`, la valeur du
 * navigateur arrive au montage — le CSS, lui, a déjà démonté le mécanisme sans
 * attendre JavaScript.
 */
export function useMouvementReduit(): boolean {
  const [reduit, setReduit] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const majSuiviReglage = () => setReduit(mq.matches);
    majSuiviReglage();
    mq.addEventListener("change", majSuiviReglage);
    return () => mq.removeEventListener("change", majSuiviReglage);
  }, []);

  return reduit;
}
