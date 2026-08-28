import SwiftUI

/// Fades the bottom of a scrolling list into the panel's ground instead of cutting the
/// last visible row off hard. Only while the content overflows the visible frame — a
/// list that fits should not have its last row dimmed for no reason.
///
/// Usage: `.scrollFadeContent(height: $h)` on the ScrollView's content and
/// `.scrollFade(contentHeight: h)` on the ScrollView. The content height travels
/// through a binding rather than a preference: TaskListView's `.onDrop` wraps the
/// content in an AppKit-backed view that never passes preferences up.
extension View {
    func scrollFadeContent(height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height.wrappedValue = $0 }
    }

    func scrollFade(contentHeight: CGFloat) -> some View {
        modifier(ScrollFade(contentHeight: contentHeight))
    }
}

struct ScrollFade: ViewModifier {
    /// Height of the faded strip at the bottom.
    static let height: CGFloat = 36

    let contentHeight: CGFloat
    @State private var frameHeight: CGFloat = 0

    private var overflows: Bool { contentHeight > frameHeight + 1 }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { frameHeight = $0 }
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    if overflows {
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: ScrollFade.height)
                    }
                }
            }
    }
}
