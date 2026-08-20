# Menu Bar To-Do

A native macOS status-bar to-do app (Swift, SwiftUI hosted in a borderless AppKit panel hanging
from an `NSStatusItem`), implemented from the Claude Design file **Menu Bar To-Do.dc.html**.

Why a custom panel instead of `NSPopover`: the popover animates size changes on its own clock and
tears its window down when content animates while it resizes, which showed as a flicker when a
row slid out. `PanelWindowController` sets the window frame directly (top-anchored, vibrancy,
12 pt radius, shadow, no arrow — matching the design); while a row collapses it follows the
animating content, coalesced to one frame update per display cycle so nothing jitters.

- Lives only in the menu bar (no Dock icon, no windows). Click the list icon to open the panel; click anywhere else to dismiss.
- Open tasks grouped by due date (Überfällig / Heute / Morgen / weekday / date), drag & drop between groups or rows.
  The insertion line previews the exact slot (top half of a row → before it, bottom half → after it, group header → first, group end → last).
- Filter menu above the list: Kein Filter / Überfällig / Heute (range tasks count as "Heute" while today is inside the range).
- Web-like affordances: pointing-hand cursor on everything clickable, grab cursor on drag handles, clicking outside a text field unfocuses it.
- Add / edit tasks with title, description, "Heute"/"Morgen" chips and a scrollable calendar with single-day or
  range selection (current month + four ahead, widened so the current selection is always reachable).
- Checking a task off plays a check animation + a synthesized two-note chime (`Sound.swift`, no asset); after 0.6 s the row
  fades out (0.2 s), then collapses to zero height (0.25 s, its group header too if it was the last row) and is removed only
  once invisible — no jump, no flicker. The collapse is an `Animatable` modifier so layout really interpolates and the panel
  window follows it frame by frame.
- Drag tasks by their grip handle (the six dots); a single list-level drop target computes the slot from the pointer.
- Tasks without a description show "Erstellt am …"; the "Erledigt" list shows "Erledigt am …" and restores with one tap.
- Tasks persist as JSON in `~/Library/Application Support/MenuBarToDo/tasks.json` (seeded with the design's sample
  data on first launch). A file that fails to load is moved aside as `tasks.corrupt-<timestamp>.json` — never overwritten.
- Right-click (or Control-click) the status item → *Menu Bar To-Do beenden* to quit.

Requires macOS 14+ and Xcode 15+ (built with Xcode 26.5 / Swift 6.3).

## Build & run

```sh
Scripts/build-app.sh --run      # swift build -c release → build/MenuBarToDo.app, then launches it
```

Or open it in Xcode: `open Package.swift`, pick the *MenuBarToDo* scheme and run.
(When run straight from Xcode without the bundle, the app still hides its Dock icon because it sets the
accessory activation policy in code.)

> Using Hidden Bar / Bartender / Ice? New status items start out in the hidden section — drag the
> list icon into the visible area once.

## Project layout

```
Package.swift                      SwiftPM manifest (macOS 14, single executable target)
Sources/MenuBarToDo/
  main.swift                       NSApplication bootstrap
  AppDelegate.swift                status item, main menu, debug preview window
  PanelWindowController.swift      borderless floating panel (sizing, transient dismissal, Esc)
  Day.swift                        calendar-day value type ("yyyy-MM-dd" in JSON)
  Models.swift                     TodoTask / DoneTask, JSON persistence, design-time settings
  Labels.swift                     German date labels (port of the design's fmt / rangeText)
  Sound.swift                      synthesized completion chime (AVAudioEngine)
  TaskStore.swift                  @Observable store: tasks, routing, draft, drag state
  Views/Theme.swift                design tokens + shared controls (chips, buttons, insertion line)
  Views/PanelView.swift            root switch (list / add / edit / done) + footer + empty state
  Views/TaskListView.swift         grouped list, drag & drop delegates, drop-zone styles
  Views/TaskFormView.swift         add / edit form
  Views/CalendarView.swift         5-month scrolling calendar with range selection
  Views/DoneListView.swift         completed tasks
Resources/Info.plist               LSUIElement = true (menu-bar-only app)
Scripts/build-app.sh               assembles and ad-hoc signs the .app bundle
Scripts/snapshot.sh                renders a single view to PNG (for visual checks)
Scripts/capture-frames.sh          captures a burst of frames of the real panel while a debug route plays
reference-web/                     faithful HTML/CSS/JS port of the design, kept as a pixel reference
```

## Design-time options

The `.dc.html` exposes three props; they live in `Settings` (`Models.swift`) and default to the design's defaults:

| Setting            | Values                                                              | Default        |
|--------------------|---------------------------------------------------------------------|----------------|
| `dateFormat`       | `.relative` ("Heute", "Fr.") / `.absolute` ("22. Aug")              | `.relative`    |
| `showDescriptions` | `true` / `false`                                                    | `true`         |
| `dropZoneStyle`    | `.insertionLine` / `.dashedFrame` / `.header` / `.emptySlot`        | `.insertionLine` |
| `completionSound`  | `true` / `false`                                                    | `true`         |

## Debug helpers

```sh
MENUBAR_TODO_AUTO_OPEN=1      build/MenuBarToDo.app/Contents/MacOS/MenuBarToDo   # open the panel on launch
MENUBAR_TODO_PREVIEW_WINDOW=1 build/MenuBarToDo.app/Contents/MacOS/MenuBarToDo   # UI in a normal window
MENUBAR_TODO_PREVIEW_POPOVER=1  (with the above) also opens the real floating panel next to it
MENUBAR_TODO_LOG_SIZES=1        logs every panel window resize
MENUBAR_TODO_SLOWMO=6           stretches the check-off animation 6× (to inspect it frame by frame)
Scripts/snapshot.sh calendar out.png     # list | add | calendar | edit | done | filter | filter-empty | drag-group | drag-row
Scripts/capture-frames.sh complete-anim frames/ 2.4   # frame burst of a check-off
```

## Distribution

`build-app.sh` signs ad-hoc, which is fine for local use. For sharing, sign with a Developer ID
certificate and notarize, or wrap the package in an Xcode app target and archive from there.
