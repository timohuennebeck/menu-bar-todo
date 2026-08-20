#!/bin/zsh
# Builds the release binary with SwiftPM and wraps it in a runnable .app bundle.
#   Scripts/build-app.sh            → build/MenuBarToDo.app
#   Scripts/build-app.sh --run      → build, then launch it
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

if [[ "${1:-}" == "--run" ]]; then
  pkill -x MenuBarToDo 2>/dev/null || true
  open "$APP"
fi
