#!/bin/zsh
# Semantic lint with swift-format. Pretty-printer layout diagnostics are dropped
# because the codebase deliberately uses a dense style; `.swift-format` holds the rules.
set -euo pipefail
cd "${0:A:h}/.."
paths=("$@"); (( $# )) || paths=(Sources Tests)
layout='\[(Indentation|LineLength|AddLines|RemoveLine|Spacing|TrailingComma|TrailingWhitespace|EndOfLineComment)\]'
output=$(xcrun swift-format lint --recursive --parallel --no-color-diagnostics "${paths[@]}" 2>&1 | grep -Ev "$layout" || true)
if [[ -n "$output" ]]; then print -r -- "$output"; exit 1; fi
print "lint: clean"
