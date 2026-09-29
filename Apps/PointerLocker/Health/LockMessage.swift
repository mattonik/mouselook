/// A lock change from the polyfill: which way, and whether WebKit's own
/// pointer lock holds it (then WebKit delivers mouse movement, not MouseBridge).
struct LockMessage: Equatable {
    let locked: Bool
    let native: Bool

    init(locked: Bool, native: Bool) {
        self.locked = locked
        self.native = native
    }

    init?(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "lock": locked = true
        case "unlock": locked = false
        default: return nil
        }
        native = body["mode"] as? String == "native"
    }
}
