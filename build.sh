#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD="$ROOT/build"
APP="$BUILD/嗷嗷状态栏歌词.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

clang -fobjc-arc -Os -Werror -mmacosx-version-min=13.0 -Wl,-dead_strip \
  -framework AppKit -framework Foundation \
  -I "$ROOT/Sources/MenuLyrics" \
  "$ROOT/Sources/MenuLyrics/main.m" \
  "$ROOT/Sources/MenuLyrics/MLAppDelegate.m" \
  "$ROOT/Sources/MenuLyrics/MLLyricsClient.m" \
  "$ROOT/Sources/MenuLyrics/MLLyricsCore.m" \
  -o "$APP/Contents/MacOS/MenuLyrics"
strip -x "$APP/Contents/MacOS/MenuLyrics"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
