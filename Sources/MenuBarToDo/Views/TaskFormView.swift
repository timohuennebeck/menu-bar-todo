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
                Text(mode == .add ? "Task hinzufügen" : "Task bearbeiten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
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
                    .onSubmit { store.submitDraft() }
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
                    SectionLabel(text: "Fällig")
                    HStack(spacing: 6) {
                        Chip(title: store.draft.due.map { German.rangeText($0, store.draft.due2) } ?? "Kein Datum",
                             style: .accent) {
                            store.toggleCalendar()
                        }
                        Spacer(minLength: 0)
                    }
                    if store.draft.calendarOpen {
                        CalendarView()
                    }
                }

                PrimaryButton(title: mode == .add ? "Task hinzufügen" : "Speichern",
                              enabled: store.draft.isReady) {
                    store.submitDraft()
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
