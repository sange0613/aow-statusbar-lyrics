#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/build/嗷嗷状态栏歌词.app"
DIST="$ROOT/dist"
STAGING="$DIST/dmg-root"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$DIST/嗷嗷状态栏歌词-$VERSION.dmg"
ZIP="$DIST/嗷嗷状态栏歌词-$VERSION.zip"

"$ROOT/build.sh" >/dev/null
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING" "$DIST"
cp -R "$APP" "$STAGING/嗷嗷状态栏歌词.app"
ln -s /Applications "$STAGING/应用程序"

hdiutil create -volname "嗷嗷状态栏歌词" \
  -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$ZIP"
echo "$DMG"
echo "$ZIP"
