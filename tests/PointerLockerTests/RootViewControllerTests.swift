import XCTest
@testable import PointerLocker

@MainActor
final class RootViewControllerTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        savedDefaults = Settings.defaults
        let suite = "RootViewControllerTests.\(UUID())"
        Settings.defaults = UserDefaults(suiteName: suite)!
        Settings.defaults.removePersistentDomain(forName: suite)
        Settings.serviceID = "geforcenow"
    }

    override func tearDown() {
        window?.rootViewController?.dismiss(animated: false)
        (window?.rootViewController as? RootViewController)?.browser?.tearDown()
        window?.isHidden = true
        window = nil
        Settings.defaults = savedDefaults
        super.tearDown()
    }

    func testTheSetupGuideLeavesTheGameInTheWindow() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        window = UIWindow(windowScene: scene)
        let root = RootViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let browser = try XCTUnwrap(root.browser, "a chosen service opens the browser")

        root.showSetupGuide()
        let presented = expectation(description: "setup guide presented")
        func check() {
            if root.presentedViewController?.isBeingPresented == false { presented.fulfill() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: check) }
        }
        check()
        wait(for: [presented], timeout: 5)

        XCTAssertNotNil(browser.view.window, "a game under the guide must keep running, not go hidden")
        XCTAssertNil(root.childViewControllerForPointerLock, "the game can't take the pointer from the guide")
    }
}
