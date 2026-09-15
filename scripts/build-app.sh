#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
scripts/swift.sh build -c "$configuration" --product Elmers
app_bundle="$PWD/dist/Elmers.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp ".build/$configuration/Elmers" "$app_bundle/Contents/MacOS/Elmers"
cp Resources/Info.plist "$app_bundle/Contents/Info.plist"
codesign --force --sign - "$app_bundle"
printf 'Built %s\n' "$app_bundle"
