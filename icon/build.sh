#!/bin/sh
# Rebuilds icon/AppIcon.icns from icon/AppIcon.html.
#
# Rasterizes the tile with the WebKit that ships with macOS (via render.swift —
# the design is CSS + inline SVG, so a browser engine is the faithful renderer)
# and assembles the .iconset and .icns with the stock sips/iconutil. No Chrome,
# no third-party tools. Re-run after editing AppIcon.html.
#
# Invoked by `make icon` (and by `make app`, which depends on it).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
trap 'rm -rf "$WORK"' EXIT

# render <cssSize> <glow> <outWidth> <out.png>
# cssSize is the authored tile size (keeps the design's fixed 1px bevel in
# proportion); outWidth is the rendered pixel width. On a Retina display the
# snapshot comes out at 2x outWidth — harmless, sips downscales to exact sizes.
# glow is the design's per-size center-glow blur (viewBox units).
render() {
  swift "$HERE/render.swift" "file://$HERE/AppIcon.html?px=$1&glow=$2" "$1" "$3" "$4"
}

# One master per glow band, each sized for the largest slot cut from it, so the
# center stays legible at small sizes instead of blooming into a smear.
render 256 11 1024 "$WORK/mA.png"   # 1024, 512
render 64  4  256  "$WORK/mB.png"   # 256, 128
render 16  0  64   "$WORK/mC.png"   # 64, 32, 16

# iconset slots: (target px : source master to downscale from)
scale() { sips -z "$1" "$1" "$2" --out "$SET/$3" >/dev/null; }
scale 1024 "$WORK/mA.png" icon_512x512@2x.png
scale 512  "$WORK/mA.png" icon_512x512.png
scale 512  "$WORK/mA.png" icon_256x256@2x.png
scale 256  "$WORK/mB.png" icon_256x256.png
scale 256  "$WORK/mB.png" icon_128x128@2x.png
scale 128  "$WORK/mB.png" icon_128x128.png
scale 64   "$WORK/mC.png" icon_32x32@2x.png
scale 32   "$WORK/mC.png" icon_32x32.png
scale 32   "$WORK/mC.png" icon_16x16@2x.png
scale 16   "$WORK/mC.png" icon_16x16.png

iconutil -c icns "$SET" -o "$HERE/AppIcon.icns"
echo "built: $HERE/AppIcon.icns"
