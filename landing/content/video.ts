import { existsSync } from "node:fs";
import { join } from "node:path";

/** La vidéo de huit secondes, filmée sur un vrai MacBook. Le scénario plan par
    plan est dans propositions/video-scenario.html. Les deux fichiers se posent
    dans public/video/ sous ces noms : au build suivant, la page les sert.
    Tant qu'il en manque un, elle montre l'encoche dessinée à la place. */
export const VIDEO = { mp4: "video/bouncer-bascule.mp4", poster: "video/bouncer-bascule.jpg" } as const;

export const videoPrete = () => Object.values(VIDEO).every((f) => existsSync(join(process.cwd(), "public", f)));
