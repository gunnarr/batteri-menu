#!/bin/bash
# Renders Resources/icon/icon.html to Resources/AppIcon.icns. Needs Google Chrome.
set -euo pipefail
cd "$(dirname "$0")/../Resources/icon"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --screenshot=icon-1024.png --window-size=1024,1024 --hide-scrollbars \
  --disable-gpu --default-background-color=00000000 "file://$(pwd)/icon.html" 2>/dev/null
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o ../AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
