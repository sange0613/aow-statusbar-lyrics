#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
mkdir -p "$ROOT/.build/manual"
for suite in Core Client App; do
  extra=()
  if [[ "$suite" != Core ]]; then
    extra+=("$ROOT/Sources/MenuLyrics/MLLyricsClient.m")
  fi
  if [[ "$suite" == App ]]; then
    extra+=("$ROOT/Sources/MenuLyrics/MLAppDelegate.m")
  fi
  clang -fobjc-arc -Werror -framework Foundation -framework AppKit -I "$ROOT/Sources/MenuLyrics" \
    "$ROOT/Tests/${suite}Tests.m" "$ROOT/Sources/MenuLyrics/MLLyricsCore.m" "${extra[@]}" \
    -o "$ROOT/.build/manual/${suite}Tests"
  "$ROOT/.build/manual/${suite}Tests"
done
