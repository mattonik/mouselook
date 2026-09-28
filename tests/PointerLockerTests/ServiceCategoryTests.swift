import XCTest
@testable import PointerLocker

final class ServiceCategoryTests: XCTestCase {
    func testEachServiceBelongsToAWorld() {
        XCTAssertEqual(ServiceProfile.geforceNow.category, .play)
        XCTAssertEqual(ServiceProfile.figma.category, .create)
    }

    func testTheChooserGroupsPlayBeforeCreateAndHidesEmptyGroups() {
        let groups = ServiceCategory.groups(of: [.figma, .geforceNow])
        XCTAssertEqual(groups.map(\.category), [.play, .create])
        XCTAssertEqual(groups.map { $0.services.map(\.id) }, [["geforcenow"], ["figma"]])
        XCTAssertEqual(ServiceCategory.groups(of: [.figma]).map(\.category), [.create], "no empty Play heading")
    }

    func testWelcomeCardsListTheirServices() {
        XCTAssertEqual(ServiceCategory.play.serviceNames(in: ServiceProfile.selectable), "GeForce NOW")
        XCTAssertEqual(ServiceCategory.create.serviceNames(in: ServiceProfile.selectable), "Figma")
        XCTAssertEqual(ServiceCategory.play.serviceNames(in: [.geforceNow, .geforceNow]), "GeForce NOW, GeForce NOW")
    }

    func testOnlyPlayServicesHaveAGameSessionInSettings() {
        XCTAssertTrue(ServiceProfile.geforceNow.category.hasGameSession)
        XCTAssertFalse(ServiceProfile.figma.category.hasGameSession)
    }

    func testSettingsNamesTheServiceTheWayItIsUsed() {
        XCTAssertEqual(ServiceCategory.play.settingsLabel, "Playing on")
        XCTAssertEqual(ServiceCategory.create.settingsLabel, "Working in")
    }
}
