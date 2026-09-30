/// The two worlds Mouselook serves, shown side by side on Welcome and as
/// headings in the chooser: design and 3D tools first, then cloud games.
enum ServiceCategory: CaseIterable {
    case create, play

    var title: String {
        switch self {
        case .play: "Play"
        case .create: "Create"
        }
    }

    /// What the mouse does in this world (Welcome card).
    var summary: String {
        switch self {
        case .play: "Aim and look around in cloud games."
        case .create: "Pan, zoom and use shortcuts in design tools."
        }
    }

    var symbol: String {
        switch self {
        case .play: "gamecontroller.fill"
        case .create: "pencil.and.outline"
        }
    }

    /// Settings ▸ Service: how the current service is named.
    var settingsLabel: String {
        switch self {
        case .play: "Playing on"
        case .create: "Working in"
        }
    }

    /// Games stream a session that must survive app switches (keep-alive,
    /// voice chat); tools save as you go.
    var hasGameSession: Bool { self == .play }

    /// The services in this world, as a comma-separated list for Welcome.
    func serviceNames(in services: [ServiceProfile]) -> String {
        services.filter { $0.category == self }.map(\.name).joined(separator: ", ")
    }

    /// Services grouped by world, Create first; worlds without services are left out.
    static func groups(of services: [ServiceProfile]) -> [(category: ServiceCategory, services: [ServiceProfile])] {
        allCases.compactMap { category in
            let members = services.filter { $0.category == category }
            return members.isEmpty ? nil : (category, members)
        }
    }
}
