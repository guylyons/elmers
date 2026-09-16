#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Command Line Tools 27.0 ship a macOS 27 SDK whose SwiftUI declares @State as a
# macro, but the tools do not include the SwiftUIMacros plugin, so the app fails
# to compile. Build against the macOS 26 SDK while it is installed alongside.
pinned_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -z "${SDKROOT:-}" && -d "$pinned_sdk" ]]; then export SDKROOT="$pinned_sdk"; fi
exec swift "$@" --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache" --config-path "$PWD/.build/swiftpm-config" --security-path "$PWD/.build/swiftpm-security"
