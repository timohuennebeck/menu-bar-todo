#!/bin/zsh
# Renders one panel view to a PNG without touching the menu bar.
#   Scripts/snapshot.sh <list|add|calendar|edit|done|filter|filter-empty|drag-group|drag-row> <out.png>
# Requires a prior Scripts/build-app.sh and Screen Recording permission for the terminal.
set -euo pipefail

ROUTE="${1:-list}"
OUT="${2:-snapshot-$ROUTE.png}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/MenuBarToDo.app/Contents/MacOS/MenuBarToDo"
LOG="$(mktemp)"

pkill -x MenuBarToDo 2>/dev/null || true
MENUBAR_TODO_PREVIEW_WINDOW=1 MENUBAR_TODO_PREVIEW_ROUTE="$ROUTE" "$BIN" >"$LOG" 2>&1 &
PID=$!

for _ in {1..40}; do
  if grep -q PREVIEW_WINDOW_ID "$LOG"; then break; fi
  sleep 0.1
done
sleep 0.8  # let SwiftUI settle / focus ring appear

WID="$(grep PREVIEW_WINDOW_ID "$LOG" | head -1 | cut -d= -f2)"
if [[ -z "$WID" ]]; then
  echo "Preview window did not appear:"; cat "$LOG"; kill "$PID" 2>/dev/null || true; exit 1
fi

screencapture -x -o -l"$WID" "$OUT"
kill "$PID" 2>/dev/null || true
rm -f "$LOG"
echo "Wrote $OUT"
