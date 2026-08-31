#!/bin/bash
# Build Bouncer.app depuis le Swift Package — pas d'Xcode, ligne de commande uniquement.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="io.github.donpaco13.bouncer"
# Ce certificat auto-signé doit être TRUSTÉ dans le trousseau, sinon rien ne marche :
#   security add-trusted-cert -r trustRoot -p codeSign \
#     -k ~/Library/Keychains/login.keychain-db <cert.pem>
# Sans le trust, TCC ne peut pas valider la designated requirement, retombe sur le CDHash du
# binaire — qui change à chaque build — et l'autorisation Accessibilité ne s'applique JAMAIS,
# tout en restant cochée dans les Réglages. Symptôme piège : visuellement autorisé,
# fonctionnellement refusé. Renommer ce CN oblige à refaire le trust ET un
# `tccutil reset Accessibility io.github.donpaco13.bouncer`.
CERT_CN="Bouncer Local Signing"

swift build -c release

APP="Bouncer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Bouncer "$APP/Contents/MacOS/Bouncer"

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
# But : que TCC/Accessibilité reconnaisse LA MÊME app entre deux builds. Sans certificat
# stable, la signature ad-hoc du linker change de designated requirement à chaque build
# (basé sur le hash du binaire), forçant à ré-autoriser l'app à chaque itération.
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

# Relance : sans ça, chaque itération coûte deux gestes manuels (quitter, rouvrir). Le pkill vise
# le binaire par son chemin complet pour ne pas toucher un homonyme.
pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true
sleep 0.3
open "$APP"
echo "🔄 Bouncer relancée"
