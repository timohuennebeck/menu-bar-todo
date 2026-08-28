#!/bin/zsh
# Builds the release binary with SwiftPM and wraps it in a runnable .app bundle.
#   Scripts/build-app.sh            → build/MenuBarToDo.app
#   Scripts/build-app.sh --run      → build, then launch it
#   Scripts/build-app.sh --install  → build, copy to /Applications, register as login item, launch it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product MenuBarToDo

APP="$ROOT/build/MenuBarToDo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/MenuBarToDo" "$APP/Contents/MacOS/MenuBarToDo"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so macOS runs it locally; replace "-" with a Developer ID for distribution.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

case "${1:-}" in
  --run)
    pkill -x MenuBarToDo 2>/dev/null || true
    open "$APP"
    ;;
  --install)
    INSTALLED="/Applications/MenuBarToDo.app"
    pkill -x MenuBarToDo 2>/dev/null || true
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    echo "Installed $INSTALLED"
    # Register as a login item (idempotent: skip if already present).
    osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
  if not (exists login item "MenuBarToDo") then
    make login item at end with properties {path:"/Applications/MenuBarToDo.app", hidden:false}
  end if
end tell
APPLESCRIPT
    echo "Registered as login item"
    open "$INSTALLED"
    ;;
esac
