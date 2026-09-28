import XCTest
@testable import PointerLocker

@MainActor
final class LaunchRouteTests: XCTestCase {
    private var savedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedDefaults = Settings.defaults
        let suite = "LaunchRouteTests.\(UUID())"
        Settings.defaults = UserDefaults(suiteName: suite)!
        Settings.defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        Settings.defaults = savedDefaults
        super.tearDown()
    }

    func testFirstLaunchShowsOnboarding() {
        XCTAssertNil(Settings.serviceID, "nothing stored on a fresh install")
        XCTAssertEqual(LaunchRoute.resolve(serviceID: Settings.serviceID), .onboarding)
    }

    func testAChosenServiceOpensDirectly() {
        XCTAssertEqual(LaunchRoute.resolve(serviceID: "geforcenow"), .browser("geforcenow"))
    }

    func testUnknownOrInternalServicesGoBackToOnboarding() {
        XCTAssertEqual(LaunchRoute.resolve(serviceID: "removed-in-a-later-version"), .onboarding)
        XCTAssertEqual(LaunchRoute.resolve(serviceID: "generic"), .onboarding, "not user-selectable")
    }

    func testFinishingOnboardingSavesTheChoice() {
        OnboardingCompletion.finish(with: .geforceNow)
        XCTAssertEqual(Settings.serviceID, "geforcenow")
        XCTAssertEqual(LaunchRoute.resolve(serviceID: Settings.serviceID), .browser("geforcenow"))
    }
}
