#!/bin/bash
# Build Bouncer.app depuis le Swift Package — pas d'Xcode, ligne de commande uniquement.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="io.github.donpaco13.bouncer"
# Certificat auto-signé, persistant dans le trousseau. Il n'a PAS besoin d'être trusté.
# Mesuré le 2026-09-03 : aucun réglage de confiance dans les trois domaines (user, admin,
# system), et l'Accessibilité fonctionne quand même. La designated requirement embarquée est
#   identifier "io.github.donpaco13.bouncer" and certificate leaf = H"30b31538..."
# soit une comparaison du hash de la feuille, pas une validation de chaîne de confiance :
# add-trusted-cert ne change rien à ce test. Ce qui compte est que le CN reste stable, car
# le renommer regénère la clé, donc le hash de feuille, donc la DR, et impose un
# `tccutil reset Accessibility io.github.donpaco13.bouncer`.
CERT_CN="Bouncer Local Signing"

swift build -c release

APP="Bouncer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Bouncer "$APP/Contents/MacOS/Bouncer"

# Le catalogue de chaînes (en.lproj / fr.lproj). SwiftPM le construit à côté du binaire ; sans
# cette copie, l'app packagée ne le trouve QUE sur cette machine — l'accesseur généré replie sur
# un chemin absolu vers .build, qui n'existe chez personne d'autre. Cf. Localisation.swift.
cp -R .build/release/Bouncer_BouncerCore.bundle "$APP/Contents/Resources/"

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
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Bouncer</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>fr</string>
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

    # -A : le trousseau autorise codesign/security à utiliser la clé sans jamais demander
    # de confirmation interactive (import et usages futurs).
    security import "$TMP_CERT_DIR/cert.p12" -k ~/Library/Keychains/login.keychain-db \
        -P bouncer-local -T /usr/bin/codesign -T /usr/bin/security -A >/dev/null
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
