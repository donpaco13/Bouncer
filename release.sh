#!/bin/bash
# Produit l'artefact distribuable versionné de Bouncer, et imprime son sha256 —
# celui que `Casks/bouncer.rb` doit porter.
set -euo pipefail
cd "$(dirname "$0")"

APP="Bouncer.app"
DIST="dist"

# On délègue la construction ET la signature à build.sh : le certificat local, la
# designated requirement et l'Info.plist n'ont qu'un seul propriétaire. Effet de bord
# assumé : build.sh installe aussi la copie dans /Applications et la relance.
./build.sh

# La version vient du bundle, pas d'une variable recopiée ici. build.sh écrit
# CFBundleShortVersionString ; la dupliquer garantirait un jour un artefact dont le nom
# ment sur son contenu.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# Une release non signée est le seul défaut qu'on ne peut pas rattraper après coup : elle
# casse l'autorisation Accessibilité chez l'utilisateur, sans message clair. On refuse de
# l'empaqueter.
codesign --verify --strict "$APP"
echo "✅ Signature vérifiée"

mkdir -p "$DIST"
ARCHIVE="$DIST/Bouncer-$VERSION.zip"
rm -f "$ARCHIVE"

# ditto, pas zip(1) : `zip` aplatit les liens symboliques et perd les métadonnées
# étendues, ce qui invalide la signature du bundle à la décompression.
ditto -c -k --keepParent "$APP" "$ARCHIVE"

SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"

echo
echo "📦 $ARCHIVE"
echo "   version : $VERSION"
echo "   sha256  : $SHA"
echo
echo "À reporter dans Casks/bouncer.rb :"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
