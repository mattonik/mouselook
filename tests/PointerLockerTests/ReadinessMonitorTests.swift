import XCTest
@testable import PointerLocker

@MainActor
final class ReadinessMonitorTests: XCTestCase {
    func testMouseStates() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        XCTAssertEqual(monitor.mouse, .notConnected)
        monitor.update(mouseCount: 1)
        XCTAssertEqual(monitor.mouse, .connected)
        monitor.mouseMoved(at: 10)
        XCTAssertEqual(monitor.mouse, .moving)
        monitor.tick(at: 10.1)
        XCTAssertEqual(monitor.mouse, .moving, "still within the pulse")
        monitor.tick(at: 10 + ReadinessMonitor.movingDuration)
        XCTAssertEqual(monitor.mouse, .connected)
    }

    func testUnpluggingWhileMovingSaysNotConnected() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        monitor.update(mouseCount: 1)
        monitor.mouseMoved(at: 0)
        monitor.update(mouseCount: 0)
        XCTAssertEqual(monitor.mouse, .notConnected)
        monitor.tick(at: 1)
        XCTAssertEqual(monitor.mouse, .notConnected)
    }

    func testMovementCountsAsAConnectedMouse() {
        // A trackpad can report deltas before GCMouse.mice() lists it.
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        monitor.mouseMoved(at: 0)
        XCTAssertEqual(monitor.mouse, .moving)
        monitor.tick(at: 1)
        XCTAssertEqual(monitor.mouse, .connected)
    }

    func testMovementArrivesThroughTheHub() {
        let hub = MouseEventHub(attachingToMice: false)
        let monitor = ReadinessMonitor(hub: hub, clock: { 5 })
        monitor.start()
        hub.emit(.moved(dx: 1, dy: 0))
        XCTAssertEqual(monitor.mouse, .moving)
        monitor.stop()
        monitor.tick(at: 6)
        hub.emit(.moved(dx: 1, dy: 0))
        XCTAssertEqual(monitor.mouse, .connected, "stopped: no longer listening")
    }

    func testKeyboard() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        XCTAssertEqual(monitor.keyboard, .notDetected)
        monitor.update(keyboardConnected: true)
        XCTAssertEqual(monitor.keyboard, .connected)
    }

    func testFullScreenInEitherOrientationButNotInAWindow() {
        let monitor = ReadinessMonitor(hub: MouseEventHub(attachingToMice: false))
        let screen = CGSize(width: 1024, height: 1366)
        monitor.update(windowSize: screen, screenSize: screen)
        XCTAssertEqual(monitor.display, .fullScreen)
        monitor.update(windowSize: CGSize(width: 1366, height: 1024), screenSize: screen)
        XCTAssertEqual(monitor.display, .fullScreen, "rotated")
        monitor.update(windowSize: CGSize(width: 1366, height: 1023.5), screenSize: screen)
        XCTAssertEqual(monitor.display, .fullScreen, "sub-point rounding")
        monitor.update(windowSize: CGSize(width: 944, height: 1260), screenSize: screen)
        XCTAssertEqual(monitor.display, .windowed, "iPadOS 26 window / Stage Manager")
    }
}
