/// What the Get ready status rows say for each state, and what VoiceOver
/// reads for them. The service's wording fills in the parts that depend on
/// what it's used for.
enum ReadinessCopy {
    struct Row: Equatable {
        let title: String
        let detail: String
        /// The title names the check and its state; the detail says what to do.
        var accessibilityLabel: String { "\(title). \(detail)" }
    }

    static func mouse(_ state: ReadinessMonitor.MouseState, _ wording: ServiceWording) -> Row {
        let title = switch state {
        case .notConnected: "Connect a mouse or trackpad"
        case .connected: "Mouse connected"
        case .moving: "Mouse is working"
        }
        let detail = state == .notConnected ? wording.mouseNeeded : wording.mouseTest
        return Row(title: title, detail: detail)
    }

    static func keyboard(_ state: ReadinessMonitor.KeyboardState, _ wording: ServiceWording) -> Row {
        let title = state == .connected ? "Keyboard connected" : "Press any key to check the keyboard"
        let detail = state == .connected ? wording.keyboardReady : "Some keyboards only show up after a key press."
        return Row(title: title, detail: detail)
    }

    static func display(_ state: ReadinessMonitor.DisplayState, _ wording: ServiceWording) -> Row {
        let title = state == .fullScreen ? "Full screen" : "Switch to full screen"
        let detail = state == .fullScreen
            ? wording.lockReady
            : "To lock the mouse, the app needs the full screen. Maximize the window, or turn on Full Screen Apps in Settings ▸ Multitasking & Gestures."
        return Row(title: title, detail: detail)
    }
}
