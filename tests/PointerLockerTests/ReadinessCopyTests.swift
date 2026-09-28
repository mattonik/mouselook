import XCTest
@testable import PointerLocker

final class ReadinessCopyTests: XCTestCase {
    private var everyRow: [ReadinessCopy.Row] {
        [ReadinessMonitor.MouseState.notConnected, .connected, .moving].map(ReadinessCopy.mouse)
            + [ReadinessMonitor.KeyboardState.notDetected, .connected].map(ReadinessCopy.keyboard)
            + [ReadinessMonitor.DisplayState.fullScreen, .windowed].map(ReadinessCopy.display)
    }

    func testVoiceOverReadsTheDetailToo() {
        for row in everyRow {
            XCTAssertTrue(row.accessibilityLabel.contains(row.title), row.title)
            XCTAssertTrue(row.accessibilityLabel.contains(row.detail), row.title)
        }
    }

    func testVoiceOverNamesEachCheckOnce() {
        XCTAssertEqual(ReadinessCopy.keyboard(.connected).accessibilityLabel,
                       "Keyboard connected. Ready for WASD.")
        for row in everyRow {
            let label = row.accessibilityLabel.lowercased()
            for word in ["mouse", "keyboard", "full screen"] where label.hasPrefix(word + ":") {
                XCTFail("prefixed label repeats the row name: \(row.accessibilityLabel)")
            }
        }
    }
}
