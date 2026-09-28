import XCTest
@testable import PointerLocker

final class HealthMonitorTests: XCTestCase {
    private var log: DiagnosticsLog!
    private var toasts: [String] = []
    private var monitor: HealthMonitor!
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        log = DiagnosticsLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("hm-\(UUID()).json"))
        toasts = []
        monitor = HealthMonitor(log: log, now: { [date] in date }) { [weak self] in self?.toasts.append($0) }
    }

    func testAProblemToastsOncePerSession() {
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        XCTAssertEqual(toasts, [HealthCheckID.scrubLock.problemMessage])
        XCTAssertEqual(monitor.results[.scrubLock], HealthStatus(result: .problem, code: "no-request", date: date))
    }

    func testOkIsRecordedWithoutAToast() {
        monitor.receive(check: "desktop-client", result: "ok", code: "desktop", host: "play.geforcenow.com", locked: false)
        XCTAssertEqual(toasts, [])
        XCTAssertEqual(monitor.results[.desktopClient]?.result, .ok)
        XCTAssertEqual(log.entries.last?.kind, "check")
        XCTAssertEqual(log.entries.last?.detail, "desktop-client ok desktop play.geforcenow.com")
    }

    func testAToastWaitsWhileThePointerIsLocked() {
        monitor.receive(check: "lock-on-click", result: "problem", code: "no-request", host: "play.geforcenow.com", locked: true)
        XCTAssertEqual(toasts, [])
        monitor.lockReleased()
        XCTAssertEqual(toasts, [HealthCheckID.lockOnClick.problemMessage])
        monitor.lockReleased()
        XCTAssertEqual(toasts.count, 1)
    }

    func testANewSessionCanToastAgain() {
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        monitor.resetSession()
        XCTAssertTrue(monitor.results.isEmpty)
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        XCTAssertEqual(toasts.count, 2)
    }

    func testSwitchingServiceDropsQueuedToast() {
        monitor.receive(check: "lock-on-click", result: "problem", code: "no-request", host: "play.geforcenow.com", locked: true)
        monitor.resetSession()
        monitor.lockReleased()
        XCTAssertEqual(toasts, [])
    }

    func testUnknownAndMalformedReportsAreIgnored() {
        monitor.receive(check: "made-up", result: "problem", code: "x", host: "evil.example", locked: false)
        monitor.receive(check: "scrub-lock", result: "maybe", code: "x", host: "www.figma.com", locked: false)
        XCTAssertEqual(toasts, [])
        XCTAssertTrue(monitor.results.isEmpty)
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testSettingsRowsFollowTheServicesChecks() {
        monitor.receive(check: "desktop-client", result: "ok", code: "desktop", host: "play.geforcenow.com", locked: false)
        let rows = monitor.rows(for: ServiceProfile.geforceNow.allHealthChecks)
        XCTAssertEqual(rows.map(\.id), [.desktopClient, .lockOnClick])
        XCTAssertEqual(rows[0].status?.result, .ok)
        XCTAssertNil(rows[1].status, "not run yet")
    }
}
