import type { Messages } from "next-intl";
import en from "./en.json";

/**
 * Ce que le portage existait pour empêcher : deux versions qui divergent. Le
 * français définit les clés, et ce fichier refuse de compiler si une traduction
 * en oublie ou en renomme une. Ce n'est pas du code mort — c'est le contrôle.
 */
export const PARITE = en satisfies Messages;
