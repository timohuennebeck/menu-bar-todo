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
                Text(mode == .add ? "Aufgabe hinzufügen" : "Aufgabe bearbeiten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if mode == .edit {
                    DeleteTaskButton()
                }
                IconButton(systemImage: "xmark", help: "Schließen", onScene: true) { store.cancel() }
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 10, trailing: 14))

            VStack(spacing: 10) {
                TextField("Titel", text: $store.draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(fieldBackground(focused: titleFocused), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(focusRing(titleFocused))
                    .focused($titleFocused)
                    .onSubmit {
                        store.submitDraft()
                        if store.route == .add { titleFocused = true }
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

                PrimaryButton(title: mode == .add ? "Aufgabe hinzufügen" : "Speichern",
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


/// Trash in the edit form's header (the macOS convention: deleting belongs to the
/// object, not the footer). Two clicks: the first arms it — red, with the question
/// as its tooltip — the second deletes. Disarms by itself after a moment, so a
/// stray click never leaves a loaded button behind. No NSAlert: a sheet out of a
/// non-activating panel is awkward, and a task is quickly recreated anyway.
private struct DeleteTaskButton: View {
    @Environment(TaskStore.self) private var store
    @State private var armed = false
    @State private var disarm: Task<Void, Never>?

    static let armedFor: Duration = .seconds(3)

    var body: some View {
        IconButton(systemImage: "trash",
                   help: armed ? "Wirklich löschen? Nochmal klicken" : "Aufgabe löschen",
                   onScene: true,
                   glyph: armed ? Theme.red : nil) {
            if armed {
                disarm?.cancel()
                store.deleteEditingTask()
            } else {
                armed = true
                disarm = Task {
                    try? await Task.sleep(for: DeleteTaskButton.armedFor)
                    if !Task.isCancelled { armed = false }
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: armed)
        .accessibilityLabel(armed ? "Wirklich löschen?" : "Aufgabe löschen")
    }
}
