import XCTest
@testable import PointerLocker

final class LockMessageTests: XCTestCase {
    func testPolyfillLockDrivesTheMouseBridge() {
        XCTAssertEqual(LockMessage(["type": "lock", "mode": "polyfill"]), LockMessage(locked: true, native: false))
    }

    func testNativeLockLeavesTheMouseToWebKit() {
        XCTAssertEqual(LockMessage(["type": "lock", "mode": "native"]), LockMessage(locked: true, native: true))
        XCTAssertEqual(LockMessage(["type": "unlock", "mode": "native"]), LockMessage(locked: false, native: true))
    }

    func testOlderMessagesWithoutModeMeanPolyfill() {
        XCTAssertEqual(LockMessage(["type": "lock"]), LockMessage(locked: true, native: false))
    }

    func testOtherMessagesAreNotLockMessages() {
        XCTAssertNil(LockMessage(["type": "health"]))
        XCTAssertNil(LockMessage([:]))
    }
}
