#!/usr/bin/env bash
# Transforme un enregistrement d'écran (⇧⌘5, QuickTime…) en asset de démo pour le README
# et la landing. Recadre, redimensionne, et sort un WebP animé + un MP4.
#
#   ./docs/demo/encoder.sh capture.mov [w:h:x:y]
#
# Le recadrage est en pixels de la vidéo source (Retina = 2x les points à l'écran).
# Sans recadrage, la vidéo est prise entière.
set -euo pipefail

SRC="${1:?usage: encoder.sh <capture.mov> [crop w:h:x:y]}"
CROP="${2:-}"
OUT="$(dirname "$0")"
LARGEUR=880   # points de large dans un README GitHub en pleine largeur

filtre="fps=20,scale=${LARGEUR}:-2:flags=lanczos"
[ -n "$CROP" ] && filtre="crop=${CROP},${filtre}"

# WebP animé : ffmpeg d'Homebrew n'embarque pas l'encodeur webp, on passe par img2webp.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ffmpeg -y -loglevel error -i "$SRC" -vf "$filtre" "$TMP/f_%04d.png"
img2webp -loop 0 -d 50 -lossy -q 72 -m 6 "$TMP"/f_*.png -o "$OUT/demo.webp"

# GIF : plus lourd, mais aucune plateforme ne s'y dérobe.
ffmpeg -y -loglevel error -i "$SRC" -vf "$filtre,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$OUT/demo.gif"

ffmpeg -y -loglevel error -i "$SRC" -vf "$filtre" \
  -c:v libx264 -pix_fmt yuv420p -crf 26 -movflags +faststart -an \
  "$OUT/demo.mp4"

ls -lh "$OUT/demo.webp" "$OUT/demo.gif" "$OUT/demo.mp4" | awk '{print $9, $5}'
