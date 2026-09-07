#!/bin/bash
# Produit l'artefact distribuable versionné de Bouncer ET réécrit `Casks/bouncer.rb`
# avec la version et le sha256 de CETTE archive-là.
#
# L'ordre est la raison d'être du script. Un cask dont le sha256 date d'un build
# antérieur installe un binaire qui ne correspond à rien, et l'erreur n'apparaît que
# chez l'utilisateur final, à `brew install`, une fois la release publiée. Tant que le
# hash se recopiait à la main, rien n'empêchait de le recopier trop tôt. Ici la seule
# chose qui écrit ces deux lignes est le bloc ci-dessous, et il s'exécute après `ditto` :
# on ne peut plus inverser l'ordre, seulement relancer le script.
set -euo pipefail
cd "$(dirname "$0")"

APP="Bouncer.app"
DIST="dist"
CASK="Casks/bouncer.rb"

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

# --- Le cask, écrit à partir de l'archive qui vient d'être produite ---
# On vérifie d'abord que les deux lignes existent en un seul exemplaire : si le cask est
# réécrit un jour et que les motifs ne collent plus, on veut échouer ici, bruyamment,
# plutôt que produire un cask silencieusement inchangé.
for MOTIF in '^  version "' '^  sha256 "'; do
    N="$(grep -c "$MOTIF" "$CASK" || true)"
    [ "$N" = "1" ] || { echo "❌ $CASK : ${N} ligne(s) '${MOTIF}', attendu 1" >&2; exit 1; }
done

sed -i '' \
    -e "s|^  version \".*\"$|  version \"$VERSION\"|" \
    -e "s|^  sha256 \".*\"$|  sha256 \"$SHA\"|" \
    "$CASK"

# Relecture : ce qui est sur le disque doit correspondre à l'archive, pas à ce qu'on
# croit avoir écrit. C'est aussi ce qui rattrape une retouche manuelle du cask faite
# après coup — le prochain `./release.sh` la signalera.
CASK_VERSION="$(sed -n 's|^  version "\(.*\)"$|\1|p' "$CASK")"
CASK_SHA="$(sed -n 's|^  sha256 "\(.*\)"$|\1|p' "$CASK")"
[ "$CASK_VERSION" = "$VERSION" ] && [ "$CASK_SHA" = "$SHA" ] \
    || { echo "❌ $CASK n'a pas pris la version/le sha256 de l'archive" >&2; exit 1; }

echo
echo "📦 $ARCHIVE"
echo "   version : $VERSION"
echo "   sha256  : $SHA"
echo
echo "✅ $CASK mis à jour depuis cette archive :"
git --no-pager diff --stat -- "$CASK" 2>/dev/null || true
echo
echo "Suite : docs/distribution/PUBLICATION.md"
