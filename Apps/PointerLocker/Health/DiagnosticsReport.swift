import Foundation

/// What Settings ▸ Advanced ▸ Copy diagnostics puts on the clipboard.
enum DiagnosticsReport {
    static func text(appVersion: String, osVersion: String, webKitVersion: String,
                     service: ServiceProfile, identity: BrowserIdentity, lockMode: String?,
                     rows: [HealthRow], entries: [DiagnosticsEntry]) -> String {
        let time = ISO8601DateFormatter()
        var lines = [
            "Mouselook diagnostics",
            "App: \(appVersion)",
            "iPadOS: \(osVersion)",
            "WebKit: \(webKitVersion)",
            "Service: \(service.name) (\(service.id))",
            "Browser identity: \(identity.userAgent ?? "WebKit default")",
            "Lock path: \(lockMode ?? "not locked yet")",
            "",
            "Checks",
        ]
        for row in rows {
            if let status = row.status {
                lines.append("\(row.title): \(status.result.rawValue) (\(status.code)) at \(time.string(from: status.date))")
            } else {
                lines.append("\(row.title): not run yet")
            }
        }
        lines += ["", "Log"]
        lines += entries.map { "\(time.string(from: $0.date)) \($0.kind) \($0.detail)" }
        return lines.joined(separator: "\n")
    }
}
