#!/bin/bash
# Build Bouncer.app depuis le Swift Package — pas d'Xcode, ligne de commande uniquement.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="io.github.donpaco13.bouncer"
# La version n'est écrite qu'ici. release.sh la relit dans l'Info.plist du bundle et en
# tire le nom de l'archive : un seul endroit à changer, et rien qui puisse diverger.
VERSION="0.1.0"
# Certificat auto-signé, persistant dans le trousseau. Il n'a PAS besoin d'être trusté.
# Mesuré le 2026-09-03 : aucun réglage de confiance dans les trois domaines (user, admin,
# system), et l'Accessibilité fonctionne quand même. La designated requirement embarquée est
#   identifier "io.github.donpaco13.bouncer" and certificate leaf = H"30b31538..."
# soit une comparaison du hash de la feuille, pas une validation de chaîne de confiance :
# add-trusted-cert ne change rien à ce test. Ce qui compte est que le CN reste stable, car
# le renommer regénère la clé, donc le hash de feuille, donc la DR, et impose un
# `tccutil reset Accessibility io.github.donpaco13.bouncer`.
# Seul endroit où le nom de l'identité est écrit. Passer au Developer ID = mettre ici
# "Developer ID Application: Nom (TEAMID)" et mettre à jour SIGNING_PIN dans release.sh.
CERT_CN="Bouncer Local Signing"

swift build -c release

# --- dSYM + upload Sentry ---
# `swift build -c release` d'un package SwiftPM ne produit AUCUN .dSYM à côté du binaire
# (contrairement à un build Xcode) : sans lui, Sentry ne peut afficher que des adresses
# hexadécimales dans les stack traces des crashs remontés en prod. dsymutil le régénère
# depuis les debug symbols embarqués dans le binaire release lui-même.
# Org et projet ne sont pas des secrets : l'org ID et le projet ID sont déjà publics dans la
# DSN embarquée (main.swift). `sentry-cli debug-files upload` accepte indifféremment l'ID ou
# le slug pour les deux, donc on prend l'ID du projet — il vient de la DSN, c'est un fait,
# pas une supposition sur le nommage. Surchargeables par l'environnement.
SENTRY_ORG_SLUG="${SENTRY_ORG:-francois-y0}"
SENTRY_PROJECT_SLUG="${SENTRY_PROJECT:-4512097601847376}"
DSYM_PATH=".build/release/Bouncer.dSYM"
rm -rf "$DSYM_PATH"
# `set -e` est actif : sans ce garde, un dsymutil en échec tuerait la fabrication du .app.
# Un dSYM manquant dégrade Sentry, il n'empêche pas de livrer l'app — même arbitrage que
# pour l'upload plus bas.
if dsymutil ".build/release/Bouncer" -o "$DSYM_PATH"; then
    echo "🩻 dSYM généré : $DSYM_PATH"
else
    echo "⚠️  Génération du dSYM échouée — les crashs Sentry n'auront que des adresses hexadécimales."
    DSYM_PATH=""
fi

if [ -z "$DSYM_PATH" ]; then
    : # dSYM absent, rien à envoyer (message déjà affiché ci-dessus)
elif ! command -v sentry-cli >/dev/null 2>&1; then
    echo "⚠️  sentry-cli introuvable, upload des symboles Sentry ignoré."
    echo "    Installer : brew install getsentry/tools/sentry-cli"
elif sentry-cli debug-files upload --org "$SENTRY_ORG_SLUG" --project "$SENTRY_PROJECT_SLUG" "$DSYM_PATH"; then
    :
else
    # On ne teste pas SENTRY_AUTH_TOKEN nous-mêmes : sentry-cli résout le token depuis
    # l'environnement OU depuis ~/.sentryclirc, et nous n'avons pas à connaître ses règles.
    # Un token absent ou périmé ne doit pas faire échouer la fabrication du .app.
    echo "⚠️  Upload des symboles Sentry échoué (build non bloqué)."
    echo "    Token : https://francois-y0.sentry.io/settings/auth-tokens/ — scope org:ci suffit,"
    echo "    à poser dans ~/.sentryclirc ([auth] token=...) ou dans SENTRY_AUTH_TOKEN."
fi

APP="Bouncer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Bouncer "$APP/Contents/MacOS/Bouncer"

# Le catalogue de chaînes (en.lproj / fr.lproj). SwiftPM le construit à côté du binaire ; sans
# cette copie, l'app packagée ne le trouve QUE sur cette machine — l'accesseur généré replie sur
# un chemin absolu vers .build, qui n'existe chez personne d'autre. Cf. Localisation.swift.
cp -R .build/release/Bouncer_BouncerCore.bundle "$APP/Contents/Resources/"
cp Sources/Bouncer/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Bouncer</string>
    <key>CFBundleDisplayName</key>
    <string>Bouncer</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Bouncer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>fr</string>
        <string>es</string>
        <string>pt_br</string>
        <string>zh_hans</string>
        <string>ja</string>
        <string>ko</string>
    </array>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# --- Signature stable (identité locale auto-signée persistante en trousseau) ---
# But : que TCC/Accessibilité reconnaisse LA MÊME app entre deux builds. Mesuré le
# 2026-09-03 : une modification du code change le CDHash (49a13c29 -> 2f03f9d2) et laisse la
# DR strictement intacte. TCC s'ancre sur la DR, l'autorisation survit donc aux rebuilds.
# Sans ce certificat, la signature ad-hoc du linker dérive à chaque build et force à
# ré-autoriser l'app à chaque itération.
if ! security find-certificate -c "$CERT_CN" >/dev/null 2>&1; then
    # En release, un nouveau certificat = une nouvelle DR = l'Accessibilité perdue chez tous
    # les utilisateurs, sans message. release.sh pose BOUNCER_RELEASE=1 pour l'interdire.
    if [ "${BOUNCER_RELEASE:-}" = "1" ]; then
        echo "❌ Identité « $CERT_CN » absente du trousseau. Refus d'en créer une nouvelle :" >&2
        echo "   la release casserait l'Accessibilité de tous les utilisateurs." >&2
        echo "   Réimporter le .p12 sauvegardé (docs/distribution/PUBLICATION.md," >&2
        echo "   « Sauvegarder l'identité de signature »), puis relancer ./release.sh." >&2
        exit 1
    fi
    echo "🔑 Certificat de signature local absent, création (une seule fois)..."
    TMP_CERT_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_CERT_DIR"' EXIT

    openssl req -x509 -newkey rsa:2048 -keyout "$TMP_CERT_DIR/key.pem" -out "$TMP_CERT_DIR/cert.pem" \
        -days 3650 -nodes -subj "/CN=$CERT_CN" \
        -addext "extendedKeyUsage=codeSigning" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1

    openssl pkcs12 -export -in "$TMP_CERT_DIR/cert.pem" -inkey "$TMP_CERT_DIR/key.pem" \
        -out "$TMP_CERT_DIR/cert.p12" -passout pass:bouncer-local >/dev/null 2>&1

    # -T : seul codesign peut utiliser la clé sans demander. Pas de -A (tout process) ni de
    # -T /usr/bin/security, qui laisserait n'importe quel script exporter la clé en silence.
    security import "$TMP_CERT_DIR/cert.p12" -k ~/Library/Keychains/login.keychain-db \
        -P bouncer-local -T /usr/bin/codesign >/dev/null
fi

codesign --force --identifier "$BUNDLE_ID" --sign "$CERT_CN" "$APP"

echo "✅ Bundle construit : $APP"

# Installation dans /Applications. Sans ça le bundle reste au fond du dossier du repo, que
# Spotlight n'indexe pas : l'app est alors introuvable autrement qu'en tapant un chemin dans un
# terminal. TCC identifie une app par sa signature et son bundle id, jamais par son chemin — la
# copie garde donc l'autorisation d'Accessibilité.
DEST="/Applications/$APP"
if [ ! -w /Applications ]; then
    mkdir -p "$HOME/Applications"
    DEST="$HOME/Applications/$APP"
fi

# Le pkill vise le binaire par son chemin pour ne pas toucher un homonyme, et couvre les deux
# emplacements : on a pu lancer aussi bien la copie installée que le bundle du repo.
pkill -f "/$APP/Contents/MacOS/" 2>/dev/null || true
sleep 0.3

rm -rf "$DEST"
cp -R "$APP" "$DEST"

open "$DEST"
echo "🔄 Bouncer installée dans $(dirname "$DEST") et relancée"
