import AppKit
import SwiftUI
import XCTest
@testable import MenuBarToDo

final class DuePickRowTests: XCTestCase {
    /// Width the quick-pick row actually gets: the 330 pt panel less the form's 14 pt
    /// padding on each side.
    private let available: CGFloat = 330 - 28
    private let gap: CGFloat = 6

    /// Measures a real Chip rather than re-deriving its font and padding here, so the
    /// test keeps meaning something if the component's metrics change.
    @MainActor
    private func chipWidth(_ title: String) throws -> CGFloat {
        let renderer = ImageRenderer(content: Chip(title: title, style: .selected) {})
        renderer.scale = 1
        return CGFloat(try XCTUnwrap(renderer.cgImage).width)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) throws -> Day {
        var parts = DateComponents()
        parts.year = y; parts.month = m; parts.day = d
        return Day(try XCTUnwrap(Calendar.current.date(from: parts)))
    }

    /// Heute, Morgen and the date all share one row, so the date chip has whatever is
    /// left. The longest thing German.rangeText can produce is a range that crosses the
    /// year, which carries the year as well as both months. If that stops fitting, dates
    /// truncate mid-word — with no error, just a chip reading "29. Dez – 14. Ja…".
    @MainActor
    func testTheLongestDateStillFitsBesideHeuteAndMorgen() throws {
        let worst = [
            try German.rangeText(day(2026, 12, 29), day(2027, 1, 14)),  // crosses the year
            try German.rangeText(day(2026, 8, 28), day(2026, 9, 5)),    // crosses a month
            try German.rangeText(day(2026, 12, 29), day(2026, 12, 31)), // longest month name
            try German.rangeText(day(2026, 9, 30), nil),                // a single far date
        ]
        let fixed = try chipWidth("Heute") + chipWidth("Morgen") + gap * 2
        for label in worst {
            let total = try fixed + chipWidth(label)
            XCTAssertLessThanOrEqual(total, available,
                                     "\"\(label)\" needs \(total) pt of \(available) — it will truncate")
        }
    }

    /// The prompt shown before a date is picked has to fit too.
    @MainActor
    func testThePromptFits() throws {
        let total = try chipWidth("Heute") + chipWidth("Morgen") + chipWidth(DuePicks.prompt) + gap * 2
        XCTAssertLessThanOrEqual(total, available)
    }
}
