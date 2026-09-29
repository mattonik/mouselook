import Foundation

enum HealthResult: String { case ok, problem }

struct HealthStatus: Equatable {
    let result: HealthResult
    let code: String
    let date: Date
}

/// Settings ▸ Service checks: one row per check.
struct HealthRow: Equatable, Identifiable {
    let id: HealthCheckID
    let title: String
    /// nil until the check has reported on this session's pages.
    let status: HealthStatus?
}

/// Collects health check results for one browser (one session: from opening a
/// service until switching service or relaunching). The first problem from a
/// check shows a toast; while the pointer is locked, the toast waits.
final class HealthMonitor {
    private(set) var results: [HealthCheckID: HealthStatus] = [:]
    private var toasted: Set<HealthCheckID> = []
    private var queued: [HealthCheckID] = []
    private let log: DiagnosticsLog
    private let now: () -> Date
    private let showToast: (String) -> Void

    init(log: DiagnosticsLog, now: @escaping () -> Date = Date.init, showToast: @escaping (String) -> Void) {
        self.log = log
        self.now = now
        self.showToast = showToast
    }

    /// A report from the page. Unknown checks or results are ignored: pages
    /// can post to the message handler too.
    func receive(check: String, result: String, code: String, host: String, locked: Bool) {
        guard let id = HealthCheckID(rawValue: check), let result = HealthResult(rawValue: result),
              Self.isShortWord(code) else { return }
        results[id] = HealthStatus(result: result, code: code, date: now())
        log.record("check", "\(id.rawValue) \(result.rawValue) \(code) \(host)", at: now())
        guard result == .problem, toasted.insert(id).inserted else { return }
        if locked { queued.append(id) } else { showToast(id.problemMessage) }
    }

    /// Codes are short words ("no-request"), never page content.
    private static func isShortWord(_ code: String) -> Bool {
        (1...32).contains(code.count) && code.allSatisfy { ("a"..."z").contains($0) || $0 == "-" }
    }

    func lockReleased() {
        let pending = queued
        queued.removeAll()
        pending.forEach { showToast($0.problemMessage) }
    }

    func resetSession() {
        results.removeAll()
        toasted.removeAll()
        queued.removeAll()
    }

    func rows(for checks: [HealthCheckID]) -> [HealthRow] {
        checks.map { HealthRow(id: $0, title: $0.title, status: results[$0]) }
    }
}
