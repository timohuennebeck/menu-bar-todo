import SwiftUI

/// Add / edit form: title, description, due chips, optional calendar.
struct TaskFormView: View {
    enum Mode { case add, edit }

    @Environment(TaskStore.self) private var store
    let mode: Mode

    @FocusState private var titleFocused: Bool
    @FocusState private var detailsFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack {
                Text(mode == .add ? "Todo hinzufügen" : "Todo bearbeiten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if mode == .edit {
                    TaskMenuButton()
                }
                IconButton(systemImage: "xmark", help: "Schließen", onScene: true) { store.cancel() }
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 10, trailing: 14))

            VStack(spacing: 10) {
                // Wraps instead of scrolling sideways. A single-line field hands a
                // too-long string to AppKit's field editor, which lays it out in its
                // own, wider rect than the static text — so the title jumped 5 pt left
                // the moment the field took focus. Wrapped, both states share one
                // layout, and a long title is readable while it is edited.
                TextField("Titel", text: $store.draft.title, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(fieldBackground(focused: titleFocused), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(focusRing(titleFocused))
                    .focused($titleFocused)
                    // Return is not a save shortcut: saving belongs to the button below,
                    // which is the only place that can tell "done typing" from "typing".
                    // It ends editing instead, like clicking off the field — and never
                    // reaches the field, which in a wrapping one would otherwise put a
                    // hard line break into the title.
                    .onKeyPress(.return) {
                        titleFocused = false
                        return .handled
                    }
                    .simultaneousGesture(TapGesture().onEnded { store.closeCalendar() })

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $store.draft.details)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.ink2)
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 9)
                        .frame(height: 74)
                        .focused($detailsFocused)
                    if store.draft.details.isEmpty {
                        Text("Beschreibung (optional)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.muted2)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .background(fieldBackground(focused: detailsFocused), in: RoundedRectangle(cornerRadius: 9))
                .overlay(focusRing(detailsFocused))
                // Clicking into a field is a click outside the calendar: collapse it. A
                // simultaneous gesture leaves the field's own click handling untouched.
                .simultaneousGesture(TapGesture().onEnded { store.closeCalendar() })

                VStack(alignment: .leading, spacing: 6) {
                    DuePickRow()
                    if store.draft.calendarOpen {
                        CalendarView()
                    }
                }

                if mode == .add {
                    // Left-aligned so the label starts where the fields do, with the
                    // switch beside it rather than adrift at the far edge. The extra
                    // space above separates it from the task's own data: this row
                    // changes what the button below does, so it groups with the button.
                    // Everything in this stack is 10 pt apart, which reads tighter
                    // between two small rows than between two bordered fields.
                    Toggle("Erstelle mehrere", isOn: $store.createsMultiple)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(Theme.accent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pointerCursor()
                        .padding(.top, 6)
                        .help("Das Formular bleibt offen, das Fälligkeitsdatum bleibt stehen")
                }

                PrimaryButton(title: mode == .add ? "Todo hinzufügen" : "Speichern",
                              enabled: store.draft.isReady) {
                    store.submitDraft()
                    // The form stays open in this mode, so put the caret back where the
                    // next task gets typed instead of leaving focus on the button.
                    if store.route == .add { titleFocused = true }
                }
            }
            .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))
        }
        .onAppear {
            // The popover becomes key a beat after it appears; defer focus accordingly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { titleFocused = true }
        }
    }

    private func fieldBackground(focused: Bool) -> Color {
        focused ? Theme.surface : Theme.fieldBackground
    }

    @ViewBuilder
    private func focusRing(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .strokeBorder(focused ? Theme.blue : .clear, lineWidth: 2)
            .allowsHitTesting(false)
    }
}

/// The due date as choices rather than a labelled value: the two days that cover
/// almost every task, plus a third chip that opens the calendar and then names
/// whatever was picked. No section label — the choices are the label.
private struct DuePickRow: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let picks = DuePicks.make(due: store.draft.due, due2: store.draft.due2, today: store.today)
        // All three fit on one row, including the longest date the formatter can
        // produce — DuePickRowTests guards that, since a wider format or more chip
        // padding would start truncating dates silently.
        HStack(spacing: 6) {
            quick(picks)
            other(picks)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func quick(_ picks: DuePicks) -> some View {
        Chip(title: "Heute", style: picks.selection == .today ? .selected : .neutral) {
            store.setDue(store.today)
        }
        Chip(title: "Morgen", style: picks.selection == .tomorrow ? .selected : .neutral) {
            store.setDue(store.today.adding(1))
        }
    }

    private func other(_ picks: DuePicks) -> some View {
        Chip(title: picks.otherLabel, style: picks.selection == .other ? .selected : .neutral) {
            store.toggleCalendar()
        }
    }
}

/// The edit form's "…" menu: destructive and rarely-used actions live behind it rather
/// than in the form itself, so nothing next to "Speichern" can be hit by accident.
///
/// The popup is an AppKit NSMenu, not SwiftUI's `Menu`: the panel is a non-activating
/// panel, and SwiftUI's Menu simply never opens there — the button takes the hover but
/// no menu appears. An NSView that pops the menu up itself works, the same way the
/// drag grip handles its own mouseDown.
private struct TaskMenuButton: View {
    @Environment(TaskStore.self) private var store
    @State private var hovering = false

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SceneChip.glyph(hovering: hovering))
            .frame(width: 22, height: 22)
            .background(SceneChip.background(hovering: hovering), in: SceneChip.shape)
            .overlay(MenuPopupArea(items: [.init(title: "Löschen", destructive: true) {
                store.deleteEditingTask()
            }]))
            .pointerCursor()
            .onHover { hovering = $0 }
            .help("Weitere Aktionen")
            .accessibilityLabel("Weitere Aktionen")
    }
}

/// Invisible click target that pops an NSMenu up under itself.
struct MenuPopupArea: NSViewRepresentable {
    struct Item {
        let title: String
        var destructive = false
        let action: () -> Void
    }

    final class MenuView: NSView {
        var items: [Item] = []

        /// Flipped, so the popup point below is the button's *bottom* edge. Unflipped it
        /// lands above the button, putting the first item under the pointer — releasing
        /// the same click then picks it, which for a destructive item is a trap.
        override var isFlipped: Bool { true }

        /// Like the drag grip: the panel is often clicked while the app is inactive, and
        /// AppKit would otherwise swallow that first click as the activating one.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let menu = NSMenu()
            for (index, item) in items.enumerated() {
                let entry = NSMenuItem(title: item.title, action: #selector(fire(_:)), keyEquivalent: "")
                entry.target = self
                entry.tag = index
                if item.destructive {
                    entry.attributedTitle = NSAttributedString(
                        string: item.title, attributes: [.foregroundColor: NSColor.systemRed])
                }
                menu.addItem(entry)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }

        @objc private func fire(_ sender: NSMenuItem) {
            items[sender.tag].action()
        }
    }

    let items: [Item]

    func makeNSView(context: Context) -> MenuView {
        let view = MenuView()
        view.items = items
        return view
    }
    func updateNSView(_ nsView: MenuView, context: Context) { nsView.items = items }
}
