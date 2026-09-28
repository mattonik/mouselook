import XCTest
@testable import PointerLocker

final class ServiceSwitchTests: XCTestCase {
    func testChoosingTheActiveServiceKeepsTheGameRunning() {
        XCTAssertFalse(ServiceSwitch.needsRebuild(current: "geforcenow", chosen: "geforcenow"))
    }

    func testChoosingAnotherServiceRebuilds() {
        XCTAssertTrue(ServiceSwitch.needsRebuild(current: "geforcenow", chosen: "xbox"))
        XCTAssertTrue(ServiceSwitch.needsRebuild(current: nil, chosen: "geforcenow"))
    }
}
