import XCTest
@testable import MenuBarToDo

final class ScrimTests: XCTestCase {
    /// The scene's nominal height in points for the real panel: 165 scene pixels of
    /// 16:10 scene at 2 pt each.
    private let nominal: CGFloat = CGFloat(165 * 10 / 16) * 2

    /// The whole point: the scrim is a function of the scene, so nothing about the
    /// panel's height can enter it. Every y below the ramp holds the same alpha
    /// however tall the panel grows — a collapsing group used to slide the alpha at
    /// every point, which read as the overlay darkening.
    func testAlphaHoldsBelowTheFade() {
        let end = Scrim.fadeEnd(nominal: nominal)
        for y in stride(from: end, through: end + 600, by: 50) {
            XCTAssertEqual(Scrim.alpha(at: y, nominal: nominal), Scrim.end, accuracy: 0.0001,
                           "alpha moved at y=\(y); the scrim must not depend on the panel's height")
        }
    }

    func testTheSkyStaysClear() {
        XCTAssertEqual(Scrim.alpha(at: 0, nominal: nominal), 0)
        XCTAssertEqual(Scrim.alpha(at: Scrim.top(nominal: nominal), nominal: nominal), 0)
    }

    /// Peaks level with the bottom of the scene, then settles back a little.
    func testShape() {
        XCTAssertEqual(Scrim.alpha(at: nominal, nominal: nominal), Scrim.mid, accuracy: 0.0001)
        XCTAssertEqual(Scrim.alpha(at: Scrim.fadeEnd(nominal: nominal), nominal: nominal),
                       Scrim.end, accuracy: 0.0001)
        XCTAssertLessThan(Scrim.end, Scrim.mid, "it settles lighter than the peak")
    }

    func testRisesMonotonicallyToThePeak() {
        let top = Scrim.top(nominal: nominal)
        var last: CGFloat = -1
        for y in stride(from: top, through: nominal, by: 4) {
            let a = Scrim.alpha(at: y, nominal: nominal)
            XCTAssertGreaterThanOrEqual(a, last, "the ramp dips at y=\(y)")
            last = a
        }
    }

    /// The gradient stop that CoreGraphics is handed has to agree with `alpha`, or the
    /// tested shape and the drawn one drift apart.
    func testGradientStopsMatchTheShape() {
        let locations = Scrim.locations(nominal: nominal)
        let top = Scrim.top(nominal: nominal), end = Scrim.fadeEnd(nominal: nominal)
        XCTAssertEqual(locations.count, 3)
        XCTAssertEqual(locations[0], 0)
        XCTAssertEqual(locations[2], 1)
        // The middle stop must land exactly on the scene's bottom edge.
        XCTAssertEqual(top + locations[1] * (end - top), nominal, accuracy: 0.0001)
    }
}
