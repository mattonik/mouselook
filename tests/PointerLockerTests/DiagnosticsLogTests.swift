import XCTest
@testable import PointerLocker

final class DiagnosticsLogTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID()).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testKeepsTheNewest200() {
        let log = DiagnosticsLog(fileURL: url)
        for i in 0..<250 { log.record("check", "entry \(i)") }
        XCTAssertEqual(log.entries.count, 200)
        XCTAssertEqual(log.entries.first?.detail, "entry 50")
        XCTAssertEqual(log.entries.last?.detail, "entry 249")
    }

    func testSurvivesARelaunch() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        DiagnosticsLog(fileURL: url).record("lock", "native", at: date)
        XCTAssertEqual(DiagnosticsLog(fileURL: url).entries, [DiagnosticsEntry(date: date, kind: "lock", detail: "native")])
    }

    func testAnUnreadableFileStartsEmpty() throws {
        try Data("not json".utf8).write(to: url)
        let log = DiagnosticsLog(fileURL: url)
        XCTAssertEqual(log.entries, [])
        log.record("service", "figma")
        XCTAssertEqual(DiagnosticsLog(fileURL: url).entries.map(\.detail), ["figma"])
    }

    func testLongDetailsAreTruncated() {
        let log = DiagnosticsLog(fileURL: url)
        log.record("check", String(repeating: "a", count: 5_000))
        XCTAssertEqual(log.entries.last?.detail.count, 200)
    }
}
