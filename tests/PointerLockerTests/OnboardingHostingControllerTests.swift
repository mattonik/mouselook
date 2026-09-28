import XCTest
@testable import PointerLocker

@MainActor
final class OnboardingHostingControllerTests: XCTestCase {
    func testRemovingOnboardingStopsTheChecks() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let parent = UIViewController()
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let host = OnboardingHostingController(start: .welcome, onFinish: { _ in }, onCancel: nil)
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(host.monitor.isRunning, "checks run while onboarding is on screen")

        // As RootViewController.remove(_:) does when the browser takes over.
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        XCTAssertFalse(host.monitor.isRunning, "no timer or listeners left behind")
    }
}
