import XCTest
@testable import PointerLocker

@MainActor
final class MouseEventHubTests: XCTestCase {
    func testEveryListenerGetsEveryEvent() {
        let hub = MouseEventHub(attachingToMice: false)
        var a: [MouseEvent] = [], b: [MouseEvent] = []
        _ = hub.addListener { a.append($0) }
        _ = hub.addListener { b.append($0) }
        hub.emit(.moved(dx: 1, dy: 2))
        hub.emit(.button(index: 0, pressed: true))
        XCTAssertEqual(a, [.moved(dx: 1, dy: 2), .button(index: 0, pressed: true)])
        XCTAssertEqual(b, a)
    }

    func testARemovedListenerHearsNothingMoreAndOthersKeepListening() {
        let hub = MouseEventHub(attachingToMice: false)
        var bridge: [MouseEvent] = [], guide: [MouseEvent] = []
        _ = hub.addListener { bridge.append($0) }
        let guideToken = hub.addListener { guide.append($0) }
        hub.emit(.moved(dx: 1, dy: 0))
        hub.remove(guideToken) // closing "Show setup guide"
        hub.emit(.moved(dx: 2, dy: 0))
        XCTAssertEqual(guide, [.moved(dx: 1, dy: 0)])
        XCTAssertEqual(bridge, [.moved(dx: 1, dy: 0), .moved(dx: 2, dy: 0)], "the game keeps its mouse")
    }

    func testMouseBridgeFollowsTheHub() {
        let hub = MouseEventHub(attachingToMice: false)
        let bridge = MouseBridge(usesDisplayLink: false, hub: hub)
        var sent: [String] = []
        bridge.send = { script, done in sent.append(script); done() }
        bridge.isActive = true
        hub.emit(.moved(dx: 3, dy: 0))
        bridge.flush()
        hub.emit(.button(index: 0, pressed: true))
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent[0].contains(#"["m",3,0]"#))
        XCTAssertTrue(sent[1].contains(#"["b",0,true]"#))
    }
}
