import XCTest
@testable import PointerLocker

final class HealthCheckTests: XCTestCase {
    func testEachServiceRunsItsChecks() {
        XCTAssertEqual(ServiceProfile.geforceNow.allHealthChecks, [.desktopClient, .lockOnClick])
        XCTAssertEqual(ServiceProfile.figma.allHealthChecks, [.scrubLock])
        XCTAssertEqual(ServiceProfile.generic.allHealthChecks, [],
                       "any page could be controller-only or plain video; only known streaming clients check lock on click")
    }

    func testThePageConfigNamesTheChecksAndReadsTheSessionPhase() {
        let script = ServiceProfile.geforceNow.healthConfigScript
        XCTAssertTrue(script.hasPrefix(#"window.__mouselookHealth={checks:["desktop-client","lock-on-click"],phase:()=>("#), script)
        XCTAssertTrue(script.contains("remote-video"), "uses the profile's session phase")
        XCTAssertTrue(script.hasSuffix(")};"))
    }

    func testToastsSayWhatHappened() {
        XCTAssertEqual(HealthCheckID.desktopClient.problemMessage,
                       "GeForce NOW didn't load its desktop version, so the mouse may not lock. Updating Mouselook usually fixes this.")
        XCTAssertEqual(HealthCheckID.lockOnClick.problemMessage,
                       "The game didn't ask for the mouse. Click into the game again. If it keeps happening, copy diagnostics in Settings ▸ Service checks.")
        XCTAssertEqual(HealthCheckID.scrubLock.problemMessage,
                       "Figma didn't lock the pointer while you dragged, so values stop at the screen edge.")
    }
}
