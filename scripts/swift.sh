#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
exec swift "$@" --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache" --config-path "$PWD/.build/swiftpm-config" --security-path "$PWD/.build/swiftpm-security"
