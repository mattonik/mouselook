import XCTest
@testable import PointerLocker

final class LockRefusalTests: XCTestCase {
    func testDescribesTheSceneAndTheTimeSinceTheLastUnlock() {
        let detail = LockRefusal.detail(sceneActive: true, screenCaptured: true, fullScreen: true, sinceLastUnlock: 0.4203)
        XCTAssertEqual(detail, "scene=active recording=yes fullscreen=yes since-unlock=420ms")
    }

    func testFirstLockOfTheSessionHasNoPreviousUnlock() {
        let detail = LockRefusal.detail(sceneActive: false, screenCaptured: false, fullScreen: false, sinceLastUnlock: nil)
        XCTAssertEqual(detail, "scene=inactive recording=no fullscreen=no since-unlock=none")
    }
}
