#!/bin/zsh
# Regenerates Resources/AppIcon.icns, the menu-bar template PNGs and a 1024 px
# preview from the SVG sources in Icon/. Uses only AppKit (its built-in SVG
# support) and iconutil; nothing is installed or downloaded.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=build
RES=Resources
mkdir -p "$BUILD" "$RES"

EXTRA_FLAGS=()
# Same workaround as build.sh for Command Line Tools with a duplicate SwiftBridging module map.
CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"
if [[ -f "$CLT_SWIFT_INC/module.modulemap" && -f "$CLT_SWIFT_INC/bridging.modulemap" ]]; then
  : > "$BUILD/empty.modulemap"
  cat > "$BUILD/overlay.yaml" <<EOF
{ "version": 0, "roots": [ { "type": "file",
  "name": "$CLT_SWIFT_INC/module.modulemap",
  "external-contents": "$PWD/$BUILD/empty.modulemap" } ] }
EOF
  EXTRA_FLAGS+=(-vfsoverlay "$PWD/$BUILD/overlay.yaml")
fi
if [[ ! -x "$BUILD/render-icon" || Icon/render-icon.swift -nt "$BUILD/render-icon" ]]; then
  swiftc -O -swift-version 5 "${EXTRA_FLAGS[@]}" -framework AppKit \
    Icon/render-icon.swift -o "$BUILD/render-icon"
fi
R="$BUILD/render-icon"

ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  "$R" Icon/AppIcon.svg "$ICONSET/icon_${s}x${s}.png" $s
  "$R" Icon/AppIcon.svg "$ICONSET/icon_${s}x${s}@2x.png" $((s*2))
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
"$R" Icon/AppIcon.svg "$BUILD/AppIcon-preview-1024.png" 1024
"$R" Icon/AppIcon.svg "$RES/AppIcon-256.png" 256      # shown in the README
"$R" Icon/MenuBarTemplate.svg "$RES/MenuBarTemplate.png" 18
"$R" Icon/MenuBarTemplate.svg "$RES/MenuBarTemplate@2x.png" 36
echo "==> $RES/AppIcon.icns, $RES/MenuBarTemplate{,@2x}.png, preview $BUILD/AppIcon-preview-1024.png"
