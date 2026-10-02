import XCTest

/// The app is iPad only. If the built Info.plist lists iPhone (1), App Store
/// Connect asks for iPhone screenshots and the app installs on iPhones.
final class DeviceFamilyTests: XCTestCase {
    func testTheAppIsIPadOnly() {
        let families = Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int]
        XCTAssertEqual(families, [2])
    }
}
