import XCTest
@testable import PointerLocker

final class DeviceFamilyTests: XCTestCase {
    /// Mouselook is iPad only. XcodeGen's iOS preset sets "1,2" on the target,
    /// which overrides a project-wide "2"; a universal build makes App Store
    /// Connect ask for iPhone screenshots and lets the app install on iPhones.
    func testTheAppDeclaresIPadOnly() {
        XCTAssertEqual(Bundle.main.infoDictionary?["UIDeviceFamily"] as? [Int], [2])
    }
}
