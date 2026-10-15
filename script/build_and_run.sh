#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
APP="$ROOT/build/嗷嗷状态栏歌词.app"
MODE="${1:-run}"
case "$MODE" in
  run|--verify|--debug|--logs|--telemetry) ;;
  *) echo "usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
pkill -x MenuLyrics 2>/dev/null || true
"$ROOT/build.sh"
if [[ "$MODE" == --debug ]]; then
  exec lldb -- "$APP/Contents/MacOS/MenuLyrics"
fi
/usr/bin/open -n "$APP"
case "$MODE" in
  --verify)
    sleep 1
    pgrep -x MenuLyrics >/dev/null
    echo 'App launch verified'
    ;;
  --logs|--telemetry)
    /usr/bin/log stream --info --style compact --predicate 'process == "MenuLyrics"'
    ;;
esac
