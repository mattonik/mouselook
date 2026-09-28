import UIKit

/// How a service is pictured in the app: an SF Symbol on a two-colour
/// gradient. Deliberately not the service's own logo or artwork.
struct ServiceArtwork {
    let symbol: String
    let colors: (top: UIColor, bottom: UIColor)
}

/// One service-specific item on the Get ready page.
struct SetupTip: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
}
