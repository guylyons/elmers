#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
scripts/swift.sh build -c "$configuration" --product Elmers
app_bundle="$PWD/dist/Elmers.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp ".build/$configuration/Elmers" "$app_bundle/Contents/MacOS/Elmers"
cp Resources/Info.plist "$app_bundle/Contents/Info.plist"
cp Resources/AboutElmers.png "$app_bundle/Contents/Resources/AboutElmers.png"
cp Resources/Toolbar.png "$app_bundle/Contents/Resources/Toolbar.png"
# Translations: one .lproj per language, looked up from the main bundle by SwiftUI and String(localized:).
find "$app_bundle/Contents/Resources" -maxdepth 1 -name "*.lproj" -exec rm -rf {} +
cp -R Resources/Localization/*.lproj "$app_bundle/Contents/Resources/"
# Build the icon from Resources/AppIcon.png whenever the artwork is newer than the compiled icon.
icns=".build/AppIcon.icns"
if [[ ! -f "$icns" || Resources/AppIcon.png -nt "$icns" ]]; then
  iconset=".build/AppIcon.iconset"; rm -rf "$iconset"; mkdir -p "$iconset"
  sips -Z 1024 Resources/AppIcon.png --out .build/AppIcon-1024.png >/dev/null
  for size in 16 32 128 256 512; do
    sips -Z "$size" .build/AppIcon-1024.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -Z $((size * 2)) .build/AppIcon-1024.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$icns"
fi
cp "$icns" "$app_bundle/Contents/Resources/AppIcon.icns"
# An ad-hoc signature's designated requirement is its cdhash, so every rebuild silently voids the Accessibility
# grant (System Settings still shows Elmers switched on). A stable local identity keeps the grant across builds.
identity="${ELMERS_SIGN_IDENTITY:-Elmers Development}"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
  codesign --force --sign "$identity" "$app_bundle"
else
  printf 'warning: no "%s" certificate; signing ad-hoc, so Accessibility must be re-granted after each build\n' "$identity" >&2
  codesign --force --sign - "$app_bundle"
fi
printf 'Built %s\n' "$app_bundle"
