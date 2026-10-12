import { ImageResponse } from "next/og";
import { getTranslations } from "next-intl/server";
import { routing, type Langue } from "@/i18n/routing";

/* L'image de partage, une par langue, dessinée au build depuis les vrais
   textes : /og/en.png et /og/fr.png. Une route plutôt que la convention
   `opengraph-image` de Next, parce qu'en export statique celle-ci écrit un
   fichier sans extension, qu'un hébergeur statique sert alors en
   application/octet-stream. Ici le nom finit par .png, le type suit. */
export const dynamic = "force-static";

const TAILLE_OG = { width: 1200, height: 630 };

export function generateStaticParams() {
  return routing.locales.map((l) => ({ fichier: `${l}.png` }));
}

export async function GET(_: Request, { params }: { params: Promise<{ fichier: string }> }) {
  const { fichier } = await params;
  const locale = fichier.replace(/\.png$/, "") as Langue;
  const t = await getTranslations({ locale, namespace: "heros" });
  const og = await getTranslations({ locale, namespace: "meta" });

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          color: "#fff",
          background: "linear-gradient(#070a22, #141a52 42%, #2e2a7e 70%, #5b3a8c)",
        }}
      >
        {/* L'encoche et la pastille de Vibe Island, à l'échelle du héros. */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            width: 460,
            height: 64,
            padding: "0 30px",
            background: "#000",
            borderRadius: "0 0 32px 32px",
            fontSize: 28,
          }}
        >
          <div style={{ display: "flex", gap: 8 }}>
            {["#30d158", "#30d158", "#ffd60a", "#64d2ff"].map((c, k) => (
              <div key={k} style={{ width: 16, height: 16, borderRadius: 8, background: c }} />
            ))}
          </div>
          <div style={{ display: "flex" }}>4 agents</div>
        </div>
        <div style={{ display: "flex", marginTop: 92, fontSize: 30, color: "rgba(255,255,255,.72)" }}>
          {t("surtitre")}
        </div>
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            marginTop: 18,
            fontSize: 92,
            lineHeight: 1.02,
            letterSpacing: -3,
          }}
        >
          <div style={{ display: "flex" }}>{t("titreLigne1")}</div>
          <div style={{ display: "flex" }}>{t("titreLigne2")}</div>
        </div>
        <div style={{ display: "flex", marginTop: 40, fontSize: 28, color: "rgba(255,255,255,.7)" }}>
          {og("accroche")}
        </div>
      </div>
    ),
    TAILLE_OG,
  );
}
