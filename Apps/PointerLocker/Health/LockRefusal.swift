import Foundation

/// The page asked for pointer lock but iPadOS didn't grant it: one diagnostics
/// line with the conditions that could explain it (Settings ▸ Copy
/// diagnostics), so a report from the field says more than "it didn't lock".
enum LockRefusal {
    static func detail(sceneActive: Bool, screenCaptured: Bool, fullScreen: Bool, sinceLastUnlock: TimeInterval?) -> String {
        let since = sinceLastUnlock.map { "\(Int(($0 * 1000).rounded()))ms" } ?? "none"
        return "scene=\(sceneActive ? "active" : "inactive") recording=\(screenCaptured ? "yes" : "no") "
            + "fullscreen=\(fullScreen ? "yes" : "no") since-unlock=\(since)"
    }
}
