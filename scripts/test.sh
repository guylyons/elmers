#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scripts/swift.sh build --product ElmersCoreChecks
exec .build/debug/ElmersCoreChecks
