import type { ReactNode } from "react";

/* Ajouter une langue = ajouter son code ici, écrire content/<code>.tsx, et
   créer app/(<code>)/layout.tsx + page.tsx sur le modèle du français. Le type
   ci-dessous est ce qui empêche les deux versions de diverger : une clé
   oubliée ou renommée d'un côté ne compile plus. C'est la raison d'être du
   portage. */
export const LOCALES = ["fr"] as const;
export type Locale = (typeof LOCALES)[number];

export type Verdict = "oui" | "non";

export type LigneCompatibilite = {
  app: string;
  version: string;
  verdict: Verdict;
  /** « Oui », « Non », « Non, prédit »… — le mot dépend de la langue. */
  libelle: string;
  note: string;
};

export type Dictionary = {
  meta: { titre: string; description: string };

  chrome: {
    evitement: string;
    codeSource: string;
    piedLigne: string;
    piedGithub: string;
    piedVersions: string;
  };

  /* Ce que les trois panneaux affichent. Générique par construction : aucune
     app tierce n'est nommée, parce que le tableau de régissabilité écrit trois
     écrans plus bas que le cycle entre deux apps n'a jamais pu être vérifié
     faute d'un second candidat. Nommer une app ici contredirait ce tableau. */
  demo: {
    noms: [string, string, string];
    agents: string;
    duree: string;
    jour: string;
    heure: string;
  };

  heros: {
    titre: ReactNode;
    chapo: ReactNode;
    installer: string;
    voirCompatibles: string;
    legendeAvant: string;
    legendeApres: string;
  };

  probleme: { titre: string; corps: ReactNode };

  geste: { titre: string; chapo: ReactNode };

  fleches: {
    titre: string;
    chapo: ReactNode;
    corps: ReactNode;
    precedente: string;
    suivante: string;
  };

  compatibilite: {
    titre: string;
    chapo: string;
    legendeTableau: string;
    colonnes: [string, string, string];
    lignes: LigneCompatibilite[];
    corps: ReactNode;
  };

  installation: {
    titre: string;
    chapo: string;
    copier: string;
    copie: string;
    echecCopie: string;
    sousLaCommande: string;
    sansHomebrew: string;
    etapesArchive: ReactNode[];
    citationGatekeeper: string;
    expliqueGatekeeper: ReactNode;
    ouvrirQuandMeme: string;
    etapesGatekeeper: ReactNode[];
    apresGatekeeper: ReactNode;
  };
};
