import XCTest
@testable import PointerLocker

final class ServiceMenuTests: XCTestCase {
    private var savedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedDefaults = Settings.defaults
        let suite = "ServiceMenuTests.\(UUID())"
        Settings.defaults = UserDefaults(suiteName: suite)!
        Settings.defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        Settings.defaults = savedDefaults
        super.tearDown()
    }

    private let figmaFile = URL(string: "https://www.figma.com/design/hPVqzzrKcyNvQJj3GXXrEx/Active?node-id=0-1")!

    func testAServicesOwnPagesAreRemembered() {
        Settings.rememberPage(figmaFile, for: .figma)
        XCTAssertEqual(Settings.lastPage(for: .figma), figmaFile)
    }

    func testPagesOnOtherSitesAreNotRemembered() {
        Settings.rememberPage(URL(string: "https://login.nvidia.com/signin")!, for: .geforceNow)
        Settings.rememberPage(URL(string: "https://accounts.google.com/o/oauth2")!, for: .figma)
        XCTAssertNil(Settings.lastPage(for: .geforceNow), "a sign-in page isn't reopened next time")
        XCTAssertNil(Settings.lastPage(for: .figma))
    }

    func testEachServiceKeepsItsOwnLastPage() {
        Settings.rememberPage(figmaFile, for: .figma)
        XCTAssertNil(Settings.lastPage(for: .geforceNow))
    }

    func testOpeningAServiceGoesToItsLastPageOrItsHome() {
        Settings.serviceID = "figma"
        XCTAssertEqual(Settings.startPage, ServiceProfile.figma.homeURL)
        Settings.rememberPage(figmaFile, for: .figma)
        XCTAssertEqual(Settings.startPage, figmaFile)
    }

    func testTheMenuListsTheServicesAndMarksTheCurrentOne() {
        let entries = ServiceSwitch.menuEntries(current: "figma")
        XCTAssertEqual(entries.map(\.name), ["GeForce NOW", "Figma"])
        XCTAssertEqual(entries.map(\.subtitle), ["Play", "Create"])
        XCTAssertEqual(entries.map(\.isCurrent), [false, true])
        XCTAssertEqual(entries.map(\.symbol), [ServiceProfile.geforceNow.artwork.symbol, ServiceProfile.figma.artwork.symbol])
    }

    func testNoServicesSectionWithOnlyOneService() {
        XCTAssertEqual(ServiceSwitch.menuEntries(current: "geforcenow", selectable: [.geforceNow]), [])
    }
}
