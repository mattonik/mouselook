import Foundation

enum ServiceSwitch {
    /// Picking the service that's already open just goes back to it; a
    /// different one needs a fresh browser (its identity is fixed at creation).
    static func needsRebuild(current: ServiceProfile.ID?, chosen: ServiceProfile.ID) -> Bool {
        current != chosen
    }

    /// Settings offers "Switch service…" only when there's another to pick.
    static func isOffered(selectable: [ServiceProfile] = ServiceProfile.selectable) -> Bool {
        selectable.count > 1
    }
}
