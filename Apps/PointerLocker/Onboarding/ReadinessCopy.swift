/// What the Get ready status rows say for each state, and what VoiceOver
/// reads for them.
enum ReadinessCopy {
    struct Row: Equatable {
        let title: String
        let detail: String
        /// The title names the check and its state; the detail says what to do.
        var accessibilityLabel: String { "\(title). \(detail)" }
    }

    static func mouse(_ state: ReadinessMonitor.MouseState) -> Row {
        let title = switch state {
        case .notConnected: "Connect a mouse or trackpad"
        case .connected: "Mouse connected"
        case .moving: "Mouse is working"
        }
        let detail = state == .notConnected
            ? "Games need a mouse or trackpad to look around. Touch alone won't work."
            : "Move it and watch the check mark. If it reacts, games can see the mouse too."
        return Row(title: title, detail: detail)
    }

    static func keyboard(_ state: ReadinessMonitor.KeyboardState) -> Row {
        let title = state == .connected ? "Keyboard connected" : "Press any key to check the keyboard"
        let detail = state == .connected ? "Ready for WASD." : "Some keyboards only show up after a key press."
        return Row(title: title, detail: detail)
    }

    static func display(_ state: ReadinessMonitor.DisplayState) -> Row {
        let title = state == .fullScreen ? "Full screen" : "Switch to full screen"
        let detail = state == .fullScreen
            ? "The mouse can lock to the game."
            : "To lock the mouse, the app needs the full screen. Maximize the window, or turn on Full Screen Apps in Settings ▸ Multitasking & Gestures."
        return Row(title: title, detail: detail)
    }
}
