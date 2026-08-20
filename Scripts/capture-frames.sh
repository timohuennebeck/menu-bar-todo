#!/bin/zsh
# Captures a burst of frames of the real floating panel while a debug route plays.
#   Scripts/capture-frames.sh <route> <out-dir> [seconds]
# e.g. Scripts/capture-frames.sh complete-anim /tmp/frames 2.2
# Requires a prior Scripts/build-app.sh and Screen Recording permission for the terminal.
set -euo pipefail
setopt null_glob

ROUTE="${1:-complete-anim}"
OUT="${2:-frames}"
SECONDS_TO_CAPTURE="${3:-2.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/MenuBarToDo.app/Contents/MacOS/MenuBarToDo"
LOG="$(mktemp)"

mkdir -p "$OUT"; rm -f "$OUT"/frame-*.png
pkill -x MenuBarToDo 2>/dev/null || true
MENUBAR_TODO_PREVIEW_WINDOW=1 MENUBAR_TODO_PREVIEW_POPOVER=1 MENUBAR_TODO_LOG_SIZES=1 \
  MENUBAR_TODO_SLOWMO="${MENUBAR_TODO_SLOWMO:-1}" MENUBAR_TODO_PREVIEW_ROUTE="$ROUTE" "$BIN" >"$LOG" 2>&1 &
PID=$!
for _ in {1..40}; do grep -q POPOVER_WINDOW_ID "$LOG" && break; sleep 0.1; done
WID="$(grep POPOVER_WINDOW_ID "$LOG" | head -1 | cut -d= -f2)"
[[ -n "$WID" ]] || { echo "panel did not appear:"; cat "$LOG"; kill "$PID" 2>/dev/null || true; exit 1; }

START=$(python3 -c 'import time;print(time.time())')
n=0
while :; do
  EL=$(python3 -c "import time;print(round(time.time()-$START,3))")
  (( $(python3 -c "print(1 if $EL > $SECONDS_TO_CAPTURE else 0)") )) && break
  screencapture -x -o -l"$WID" "$OUT/frame-$(printf %02d $n)-${EL}.png" 2>/dev/null || true
  n=$((n+1))
done
kill "$PID" 2>/dev/null || true
for f in "$OUT"/frame-*.png; do
  echo "$(basename "$f") $(sips -g pixelHeight "$f" | tail -1 | awk '{print $2}')px"
done
echo "--- app log ---"; grep -v POPOVER_WINDOW_ID "$LOG" | tail -40
rm -f "$LOG"
