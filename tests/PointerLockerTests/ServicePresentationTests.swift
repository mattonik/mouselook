import UIKit
import XCTest
@testable import PointerLocker

final class ServicePresentationTests: XCTestCase {
    func testOnboardingOffersFigmaThenGeForceNowButNotTheGenericProfile() {
        XCTAssertEqual(ServiceProfile.selectable.map(\.id), ["figma", "geforcenow"])
    }

    func testEverySelectableServiceCanBePresented() {
        for profile in ServiceProfile.selectable {
            XCTAssertFalse(profile.name.isEmpty, profile.id)
            XCTAssertFalse(profile.tagline.isEmpty, profile.id)
            XCTAssertNotNil(UIImage(systemName: profile.artwork.symbol), "\(profile.id) artwork symbol")
            XCTAssertFalse(profile.setupTips.isEmpty, profile.id)
            for tip in profile.setupTips {
                XCTAssertNotNil(UIImage(systemName: tip.symbol), "\(profile.id) tip \(tip.id) symbol")
                XCTAssertFalse(tip.title.isEmpty)
                XCTAssertFalse(tip.detail.isEmpty)
            }
            XCTAssertEqual(Set(profile.setupTips.map(\.id)).count, profile.setupTips.count, "tip ids unique")
        }
    }

    func testGeForceNowTellsYouToUse1080p() {
        let tip = ServiceProfile.geforceNow.setupTips.first { $0.id == "resolution" }
        XCTAssertEqual(tip?.title, "Set the stream to 1920×1080")
    }

    func testFigmaLeadsWithDesktopNavigation() {
        XCTAssertEqual(ServiceProfile.figma.setupTips.first?.id, "navigate")
    }

    func testFigmaTellsYouHowToScrub() {
        let tip = ServiceProfile.figma.setupTips.first { $0.id == "scrub" }
        XCTAssertEqual(tip?.title, "Drag a number's label to change it")
    }

    func testProfilesAreFoundByID() {
        XCTAssertEqual(ServiceProfile.profile(id: "figma")?.name, "Figma")
        XCTAssertEqual(ServiceProfile.profile(id: "geforcenow")?.name, "GeForce NOW")
        XCTAssertEqual(ServiceProfile.profile(id: "generic")?.id, "generic")
        XCTAssertNil(ServiceProfile.profile(id: "nope"))
    }

    func testServiceIDsAreUnique() {
        XCTAssertEqual(Set(ServiceProfile.all.map(\.id)).count, ServiceProfile.all.count)
    }
}

final class WelcomeIconTests: XCTestCase {
    func testWelcomeShowsTheAppIcon() {
        // Rendered from design/icon/mouselook.svg with the app icon (tools/render-icon.sh).
        let image = UIImage(named: "WelcomeIcon")
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width, image?.size.height)
    }
}
