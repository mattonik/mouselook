import XCTest
@testable import PointerLocker

@MainActor
final class ServiceProfileTests: XCTestCase {
    private var savedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedDefaults = Settings.defaults
        let suite = "ServiceProfileTests.\(UUID())"
        Settings.defaults = UserDefaults(suiteName: suite)!
        Settings.defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        Settings.defaults = savedDefaults
        super.tearDown()
    }

    func testGeForceNowPresentsAsSafari264OnAMac() {
        let identity = ServiceProfile.geforceNow.identity
        XCTAssertTrue(identity.userAgent?.contains("Macintosh") == true)
        XCTAssertTrue(identity.userAgent?.contains("Version/26.4 Safari/") == true)
        XCTAssertEqual(identity.platform, "MacIntel")
        XCTAssertEqual(identity.maxTouchPoints, 0)
        XCTAssertTrue(identity.desktopContentMode)
    }

    func testGenericProfileDoesNotDisguiseTheDevice() {
        XCTAssertEqual(ServiceProfile.generic.identity, .webKitDefault)
    }

    func testPageConfigCarriesTheIdentity() {
        XCTAssertEqual(
            ServiceProfile.geforceNow.pageConfigScript(useIdentity: true),
            #"window.__pointerLockerConfig={"identity":{"maxTouchPoints":0,"platform":"MacIntel"}};"#)
    }

    func testPageConfigWithoutIdentity() {
        let off = #"window.__pointerLockerConfig={"identity":null};"#
        XCTAssertEqual(ServiceProfile.geforceNow.pageConfigScript(useIdentity: false), off)
        XCTAssertEqual(ServiceProfile.generic.pageConfigScript(useIdentity: true), off)
    }

    func testCurrentProfileDefaultsToGeForceNowAndFallsBackForUnknownIDs() {
        XCTAssertEqual(ServiceProfile.current.id, "geforcenow")
        Settings.serviceID = "generic"
        XCTAssertEqual(ServiceProfile.current.id, "generic")
        Settings.serviceID = "no-such-service"
        XCTAssertEqual(ServiceProfile.current.id, "geforcenow")
    }

    func testHomeURLDefaultsToTheProfileAndCanBeOverriddenPerProfile() {
        XCTAssertEqual(Settings.homeURL, URL(string: "https://play.geforcenow.com")!)
        Settings.homeURL = URL(string: "https://play.geforcenow.com/mall/")!
        XCTAssertEqual(Settings.homeURL.absoluteString, "https://play.geforcenow.com/mall/")

        Settings.serviceID = "generic"
        XCTAssertEqual(Settings.homeURL, ServiceProfile.generic.homeURL, "another profile keeps its own home")
    }

    func testTheIdentitySettingKeepsTheOldStoredChoice() {
        XCTAssertTrue(Settings.useServiceIdentity, "on by default")
        Settings.defaults.set(false, forKey: "spoofDesktop") // written by earlier versions
        XCTAssertFalse(Settings.useServiceIdentity)
    }

    func testURLsTypedWithoutAScheme() {
        XCTAssertEqual(BrowserViewController.normalizedURL(" play.geforcenow.com ")?.absoluteString, "https://play.geforcenow.com")
        XCTAssertEqual(BrowserViewController.normalizedURL("http://x.test")?.absoluteString, "http://x.test")
        XCTAssertNil(BrowserViewController.normalizedURL("  "))
    }
}
