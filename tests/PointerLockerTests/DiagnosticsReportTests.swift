import XCTest
@testable import PointerLocker

final class DiagnosticsReportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func report() -> String {
        DiagnosticsReport.text(
            appVersion: "0.1.0 (1)", osVersion: "26.0", webKitVersion: "21622.1",
            service: .figma, identity: ServiceProfile.figma.identity, lockMode: "polyfill",
            rows: [HealthRow(id: .scrubLock, title: HealthCheckID.scrubLock.title,
                             status: HealthStatus(result: .problem, code: "no-request", date: date))],
            entries: [DiagnosticsEntry(date: date, kind: "service", detail: "figma")])
    }

    func testTheReportHasEverySection() {
        let text = report()
        for line in ["Mouselook diagnostics", "App: 0.1.0 (1)", "iPadOS: 26.0", "WebKit: 21622.1",
                     "Service: Figma (figma)", "Lock path: polyfill",
                     "Scrubbing locks the pointer: problem (no-request)", "service figma"] {
            XCTAssertTrue(text.contains(line), "missing \(line)")
        }
        XCTAssertTrue(text.contains("Chrome/"), "names the identity it presents")
    }

    func testNoAddressesInTheReport() {
        XCTAssertFalse(report().contains("://"))
    }

    func testChecksThatHaventRunSaySo() {
        let text = DiagnosticsReport.text(
            appVersion: "1", osVersion: "26.0", webKitVersion: "1", service: .geforceNow,
            identity: ServiceProfile.geforceNow.identity, lockMode: nil,
            rows: [HealthRow(id: .desktopClient, title: HealthCheckID.desktopClient.title, status: nil)], entries: [])
        XCTAssertTrue(text.contains("Desktop version loads: not run yet"))
        XCTAssertTrue(text.contains("Lock path: not locked yet"))
    }
}
