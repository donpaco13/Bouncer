import { useLocale } from "next-intl";
import { NOMS_LANGUES, routing } from "@/i18n/routing";

/**
 * Deux langues, donc un seul lien : celui vers l'autre, écrit dans l'autre.
 * Pas de menu à déplier pour un choix binaire, et pas de drapeau — un drapeau
 * nomme un pays, pas une langue.
 *
 * C'est une ancre nue, pas le `Link` de next-intl : celui-ci bascule en
 * composant client dès qu'on lui passe une langue, et réclame alors un
 * `NextIntlClientProvider` — du JavaScript et un dictionnaire envoyés au
 * navigateur pour un lien qui change de document de toute façon.
 *
 * Le chemin est relatif, et il l'est parce que `trailingSlash` garantit que
 * l'URL courante finit par « / » : la page reste juste servie depuis un
 * sous-dossier. `lang` et `hreflang` disent au lecteur d'écran et au moteur de
 * recherche que ce libellé, lui, change de langue.
 */
export function SelecteurLangue() {
  const courante = useLocale();
  const autre =
    routing.locales.find((l) => l !== courante) ?? routing.defaultLocale;

  return (
    <a
      href={`../${autre}/`}
      lang={autre}
      hrefLang={autre}
      className="border-0 text-[.9375rem] text-gris hover:text-encre"
    >
      {NOMS_LANGUES[autre]}
    </a>
  );
}
