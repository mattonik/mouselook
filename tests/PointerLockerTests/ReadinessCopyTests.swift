import XCTest
@testable import PointerLocker

final class ReadinessCopyTests: XCTestCase {
    private func everyRow(_ wording: ServiceWording) -> [ReadinessCopy.Row] {
        [ReadinessMonitor.MouseState.notConnected, .connected, .moving].map { ReadinessCopy.mouse($0, wording) }
            + [ReadinessMonitor.KeyboardState.notDetected, .connected].map { ReadinessCopy.keyboard($0, wording) }
            + [ReadinessMonitor.DisplayState.fullScreen, .windowed].map { ReadinessCopy.display($0, wording) }
    }

    private var everyWording: [ServiceWording] { ServiceProfile.all.map(\.wording) }

    func testVoiceOverReadsTheDetailToo() {
        for wording in everyWording {
            for row in everyRow(wording) {
                XCTAssertTrue(row.accessibilityLabel.contains(row.title), row.title)
                XCTAssertTrue(row.accessibilityLabel.contains(row.detail), row.title)
            }
        }
    }

    func testVoiceOverNamesEachCheckOnce() {
        XCTAssertEqual(ReadinessCopy.keyboard(.connected, ServiceProfile.geforceNow.wording).accessibilityLabel,
                       "Keyboard connected. Ready for WASD.")
        for wording in everyWording {
            for row in everyRow(wording) {
                let label = row.accessibilityLabel.lowercased()
                for word in ["mouse", "keyboard", "full screen"] where label.hasPrefix(word + ":") {
                    XCTFail("prefixed label repeats the row name: \(row.accessibilityLabel)")
                }
            }
        }
    }

    func testTheStartButtonFitsTheService() {
        XCTAssertEqual(ServiceProfile.geforceNow.wording.start, "Start playing")
        XCTAssertEqual(ServiceProfile.figma.wording.start, "Open Figma")
    }

    func testEachServiceSpeaksToItsOwnUse() {
        XCTAssertEqual(ReadinessCopy.keyboard(.connected, ServiceProfile.figma.wording).detail, "Ready for shortcuts.")
        XCTAssertTrue(ReadinessCopy.mouse(.notConnected, ServiceProfile.figma.wording).detail.hasPrefix("Figma needs"))
        XCTAssertTrue(ReadinessCopy.mouse(.notConnected, ServiceProfile.geforceNow.wording).detail.hasPrefix("Games need"))
        for profile in ServiceProfile.all where profile.id != "geforcenow" {
            let all = everyRow(profile.wording).map(\.detail) + [profile.wording.release, profile.wording.start]
            XCTAssertFalse(all.contains { $0.localizedCaseInsensitiveContains("game") }, "\(profile.id) talks about games")
        }
    }
}
