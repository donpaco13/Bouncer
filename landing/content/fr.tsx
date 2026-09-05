import type { Dictionary } from "./dictionary";
import { LIENS } from "./liens";

export const fr: Dictionary = {
  meta: {
    titre: "Bouncer — une encoche, une seule app à la fois",
    description:
      "Bouncer régit la visibilité des apps d’encoche sur MacBook. Elles restent toutes ouvertes, une seule se voit, et vous changez d’un swipe à deux doigts.",
  },

  chrome: {
    evitement: "Aller au contenu",
    codeSource: "Code source",
    piedLigne: "Bouncer, utilitaire pour macOS 14 et plus.",
    piedGithub: "GitHub",
    piedVersions: "Versions",
  },

  demo: {
    noms: ["Suivi d’agents", "Musique", "Calendrier"],
    agents: "4 agents",
    duree: "2:41",
    jour: "jeu. 14",
    heure: "11:00",
  },

  heros: {
    titre: (
      <>
        Une encoche.
        <br />
        Une seule app à la fois.
      </>
    ),
    chapo: (
      <>
        Vos apps d’encoche restent toutes ouvertes. Bouncer décide laquelle se
        voit, et vous changez d’avis d’un swipe à deux doigts.
      </>
    ),
    installer: "Installer Bouncer",
    voirCompatibles: "Voir les apps compatibles",
    legendeAvant: "Deux apps dessinent au même endroit.",
    legendeApres: "Bouncer n’en laisse qu’une sur scène.",
  },

  probleme: {
    titre: "macOS ne coordonne rien",
    corps: (
      <>
        <p>
          Vibe Island, boringNotch, Alcove, Notchy&nbsp;: chacune dessine sa
          propre pilule sous l’encoche de votre MacBook. Ouvrez-en deux, elles
          occupent le même rectangle et se superposent.
        </p>
        <p>
          Il n’existe aucune API de coordination et aucune notion d’«&nbsp;app
          d’encoche active&nbsp;».{" "}
          <strong>
            La seule sortie que macOS vous laisse, c’est de quitter l’une pour
            utiliser l’autre
          </strong>
          , puis de la relancer quand vous en avez de nouveau besoin.
        </p>
      </>
    ),
  },

  geste: {
    titre: "Deux doigts sur l’encoche",
    chapo: (
      <>
        Balayez à gauche ou à droite. L’app suivante prend la place&nbsp;; la
        précédente reste ouverte et continue de tourner.
      </>
    ),
  },

  fleches: {
    titre: "Ou deux flèches, au survol",
    chapo: (
      <>
        Si vous préférez la souris, approchez le curseur de l’encoche&nbsp;: deux
        flèches s’allument de part et d’autre du boîtier caméra. Hors survol,
        Bouncer ne recouvre rien.
      </>
    ),
    corps: (
      <p>
        Le reste vit dans la barre des menus&nbsp;: la liste des apps détectées,
        celle qui est en scène, et les réglages. Bouncer n’a ni icône dans le
        Dock ni fenêtre à gérer.
      </p>
    ),
    precedente: "App d’encoche précédente",
    suivante: "App d’encoche suivante",
  },

  compatibilite: {
    titre: "Toutes les apps ne se laissent pas régir",
    chapo: "Et ça ne dépend pas de Bouncer. Autant le savoir avant d’installer.",
    legendeTableau: "Compatibilité des apps d’encoche testées",
    colonnes: ["Application", "Version testée", "Régissable"],
    lignes: [
      {
        app: "Vibe Island",
        version: "1.0.48",
        verdict: "oui",
        libelle: "Oui",
        note: "Mesuré en direct, masquage confirmé par recomptage des fenêtres.",
      },
      {
        app: "boringNotch",
        version: "2.7.3",
        verdict: "non",
        libelle: "Non",
        note: "Mesuré en direct : l’ordre de masquage est accepté et ne change rien à l’écran.",
      },
      {
        app: "Alcove",
        version: "1.7.7",
        verdict: "non",
        libelle: "Non, prédit",
        note: "Verdict lu dans le binaire, pas confirmé de bout en bout.",
      },
      {
        app: "Notchy",
        version: "1.0.135",
        verdict: "non",
        libelle: "Non, prédit",
        note: "Verdict lu dans le binaire, pas confirmé de bout en bout.",
      },
    ],
    corps: (
      <>
        <p>
          La ligne de partage se lit dans le binaire. Une app qui laisse ses
          fenêtres dans votre Space répond au masquage. Une app qui les épingle
          dans un Space privé qu’elle crée elle-même sort du circuit standard de
          macOS&nbsp;: rien ne la déloge sans API privée, et Bouncer n’en
          utilisera pas.
        </p>
        <p>
          Bouncer teste chaque app une fois à sa découverte. Elle marque
          «&nbsp;non supportée&nbsp;» celles qui ne répondent pas, les sort du
          cycle et ne les reteste plus.
        </p>
        <p>
          Aujourd’hui, sur les quatre apps testées,{" "}
          <strong>une seule se laisse régir</strong>. Le cycle entre deux apps
          est écrit et fonctionnel, mais faute d’un second candidat, il n’a
          jamais pu être vérifié en conditions réelles. Vérifiez la vôtre avec la
          commande donnée dans le{" "}
          <a href={LIENS.readmeResistance}>README</a>.
        </p>
      </>
    ),
  },

  installation: {
    titre: "Installer",
    chapo: "macOS 14 Sonoma ou plus récent, sur un MacBook à encoche.",
    copier: "Copier",
    copie: "Copié",
    echecCopie: "Sélectionnez la ligne",
    sousLaCommande: "Bouncer s’installe dans Applications et s’ouvre normalement.",
    sansHomebrew: "Sans Homebrew",
    etapesArchive: [
      <>
        Téléchargez l’archive <code className="font-mono text-sm">.zip</code>{" "}
        depuis la <a href={LIENS.versions}>page des versions</a>.
      </>,
      <>Double-cliquez le fichier téléchargé.</>,
      <>Glissez Bouncer dans votre dossier Applications.</>,
    ],
    citationGatekeeper:
      "« macOS n’a pas pu vérifier que Bouncer ne contient pas de logiciel malveillant. »",
    expliqueGatekeeper: (
      <>
        C’est ce que vous verrez au premier lancement, et c’est normal. macOS ne
        sait pas qui a écrit Bouncer&nbsp;: Apple facture 99&nbsp;€ par an aux
        développeurs pour une identité qu’il reconnaît d’emblée, et Bouncer ne la
        paie pas. Le blocage porte sur cette identité manquante, pas sur le
        contenu de l’app&nbsp;: elle n’est ni endommagée ni infectée.
      </>
    ),
    ouvrirQuandMeme: "Pour l’ouvrir quand même, une seule fois :",
    etapesGatekeeper: [
      <>Double-cliquez Bouncer et laissez macOS refuser.</>,
      <>Ouvrez Réglages Système, puis Confidentialité et sécurité.</>,
      <>
        Descendez jusqu’au message qui parle de Bouncer, cliquez sur
        «&nbsp;Ouvrir quand même&nbsp;».
      </>,
      <>Confirmez avec votre mot de passe.</>,
    ],
    apresGatekeeper: (
      <>
        <p>
          Les lancements suivants passent directement. Par Homebrew, vous ne
          voyez pas cet écran parce que le cask retire lui-même l’attribut de
          quarantaine. C’est un contournement de Gatekeeper que nous écrivons
          nous-mêmes, et il disparaîtra le jour où Bouncer sera notarisée par
          Apple.
        </p>
        <p>
          Bouncer a besoin d’une autorisation macOS, et d’une seule&nbsp;:
          l’Accessibilité, qui lui permet de masquer les fenêtres des autres
          apps. Elle vous la demande au premier lancement.
        </p>
      </>
    ),
  },
};
