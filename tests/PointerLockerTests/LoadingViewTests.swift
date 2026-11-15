import XCTest
@testable import PointerLocker

@MainActor
final class LoadingViewTests: XCTestCase {
    func testShowsUntilHidden() {
        let view = LoadingView()
        XCTAssertTrue(view.isHidden, "hidden until the browser shows it")
        var reloads = 0
        view.show(serviceName: "Figma") { reloads += 1 }
        XCTAssertFalse(view.isHidden)
        view.hide()
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(reloads, 0)
    }
}
