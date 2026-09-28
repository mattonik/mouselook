import Foundation

struct DiagnosticsEntry: Codable, Equatable {
    let date: Date
    let kind: String
    let detail: String
}

/// The last 200 things worth knowing for a bug report: check results, which
/// lock path was used, service switches, failed loads. Host names only, never
/// page content or URL paths. Saved as JSON so it survives relaunches.
final class DiagnosticsLog {
    static let shared = DiagnosticsLog(fileURL: defaultURL)
    static let capacity = 200
    static let maxDetailLength = 200

    private(set) var entries: [DiagnosticsEntry]
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        entries = data.flatMap { try? JSONDecoder().decode([DiagnosticsEntry].self, from: $0) } ?? []
    }

    func record(_ kind: String, _ detail: String, at date: Date = Date()) {
        entries.append(DiagnosticsEntry(date: date, kind: kind, detail: String(detail.prefix(Self.maxDetailLength))))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        // A failed write keeps the entries in memory for this session.
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }

    private static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.json")
    }
}
