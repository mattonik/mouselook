import SwiftUI
import XCTest
@testable import PointerLocker

final class WelcomeLayoutTests: XCTestCase {
    func testCardsSitSideBySideOnAFullIPadAtLargeTextSizes() {
        XCTAssertFalse(WelcomeLayout.stacksCards(dynamicTypeSize: .large, horizontalSizeClass: .regular))
        XCTAssertFalse(WelcomeLayout.stacksCards(dynamicTypeSize: .xxxLarge, horizontalSizeClass: .regular))
    }

    func testCardsStackAtAccessibilityTextSizes() {
        XCTAssertTrue(WelcomeLayout.stacksCards(dynamicTypeSize: .accessibility1, horizontalSizeClass: .regular))
    }

    func testCardsStackInANarrowWindow() {
        XCTAssertTrue(WelcomeLayout.stacksCards(dynamicTypeSize: .large, horizontalSizeClass: .compact))
    }
}
