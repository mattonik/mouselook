import Foundation

enum ServiceSwitch {
    /// Picking the service that's already open just goes back to it; a
    /// different one needs a fresh browser (its identity is fixed at creation).
    static func needsRebuild(current: ServiceProfile.ID?, chosen: ServiceProfile.ID) -> Bool {
        current != chosen
    }

    /// The ⋯ menu's services section; empty when there's only one service.
    static func menuEntries(current: ServiceProfile.ID?,
                            selectable: [ServiceProfile] = ServiceProfile.selectable) -> [ServiceMenuEntry] {
        guard isOffered(selectable: selectable) else { return [] }
        return selectable.map {
            ServiceMenuEntry(id: $0.id, name: $0.name, subtitle: $0.category.title,
                             symbol: $0.artwork.symbol, isCurrent: $0.id == current)
        }
    }

    /// Settings offers "Switch service…" only when there's another to pick.
    static func isOffered(selectable: [ServiceProfile] = ServiceProfile.selectable) -> Bool {
        selectable.count > 1
    }
}

struct ServiceMenuEntry: Equatable {
    let id: ServiceProfile.ID
    let name: String
    /// The world it belongs to ("Play", "Create").
    let subtitle: String
    let symbol: String
    let isCurrent: Bool
}
