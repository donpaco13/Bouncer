import { routing } from "@/i18n/routing";

/* En export statique il n'y a pas de proxy pour négocier la langue : `/` est un
   fichier comme un autre. Il renvoie vers la langue par défaut par un
   rafraîchissement immédiat — le seul aiguillage qu'un hébergeur statique
   comprenne partout — et le lien reste cliquable si le renvoi est bloqué. Le
   chemin est relatif : la page marche aussi servie depuis un sous-dossier. */
const CIBLE = `./${routing.defaultLocale}/`;

export default function Aiguillage() {
  return (
    <>
      <meta httpEquiv="refresh" content={`0; url=${CIBLE}`} />
      <a href={CIBLE}>Bouncer</a>
    </>
  );
}
