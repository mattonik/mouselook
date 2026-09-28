import Foundation

/// What the app shows when it starts.
enum LaunchRoute: Equatable {
    case onboarding
    case browser(ServiceProfile.ID)

    /// Onboarding until a user-selectable service is stored.
    static func resolve(serviceID: String?) -> LaunchRoute {
        guard let serviceID, ServiceProfile.selectable.contains(where: { $0.id == serviceID }) else {
            return .onboarding
        }
        return .browser(serviceID)
    }
}

/// The only place onboarding's choice is saved: when the user taps
/// Start playing. Choosing a card on its own saves nothing.
enum OnboardingCompletion {
    static func finish(with profile: ServiceProfile) {
        Settings.serviceID = profile.id
    }
}
