import XCTest
@testable import PointerLocker

@MainActor
final class MouseBridgeTests: XCTestCase {
    private var sent: [String] = []
    private var pendingCompletions: [() -> Void] = []
    private var now: CFTimeInterval = 0

    private func makeBridge() -> MouseBridge {
        let bridge = MouseBridge(usesDisplayLink: false)
        bridge.clock = { [unowned self] in self.now }
        bridge.send = { [unowned self] script, done in
            self.sent.append(Self.events(in: script))
            self.pendingCompletions.append(done)
        }
        bridge.isActive = true
        return bridge
    }

    /// The page finished evaluating the oldest batch.
    private func completeOldest() {
        pendingCompletions.removeFirst()()
    }

    /// `window.__pointerLocker…batch([…])` → the events inside the array.
    private static func events(in script: String) -> String {
        guard let start = script.range(of: "batch(["), let end = script.range(of: "])", options: .backwards) else {
            return script
        }
        return String(script[start.upperBound..<end.lowerBound])
    }

    func testMovementSendsWholePixelsAndKeepsTheRemainder() {
        let bridge = makeBridge()
        bridge.handleMove(dx: 1.6, dy: 0)
        bridge.flush()
        XCTAssertEqual(sent, [#"["m",1,0]"#])
        completeOldest()

        bridge.handleMove(dx: 0.6, dy: 0) // 0.6 left over + 0.6 = 1.2
        bridge.flush()
        XCTAssertEqual(sent.last, #"["m",1,0]"#)
    }

    func testUpIsNegativeYUnlessInverted() {
        let bridge = makeBridge()
        bridge.handleMove(dx: 0, dy: 3) // GameController: +Y is up
        bridge.flush()
        XCTAssertEqual(sent, [#"["m",0,-3]"#])
        completeOldest()

        bridge.invertY = true
        bridge.handleMove(dx: 0, dy: 3)
        bridge.flush()
        XCTAssertEqual(sent.last, #"["m",0,3]"#)
    }

    func testNothingIsSentWhileInactive() {
        let bridge = makeBridge()
        bridge.isActive = false
        bridge.handleMove(dx: 10, dy: 10)
        bridge.handleButton(0, pressed: true)
        bridge.handleScroll(x: 0, y: 1)
        bridge.flush()
        XCTAssertEqual(sent, [])
    }

    func testOnlyOneBatchIsInFlightAndMovementMergesMeanwhile() {
        let bridge = makeBridge()
        bridge.handleMove(dx: 5, dy: 0)
        bridge.flush()
        bridge.handleMove(dx: 3, dy: 0)
        bridge.flush()
        bridge.handleMove(dx: 4, dy: 0)
        bridge.flush()
        XCTAssertEqual(sent, [#"["m",5,0]"#], "must wait for the page before sending more")

        completeOldest() // the page caught up: the merged movement goes out at once
        XCTAssertEqual(sent, [#"["m",5,0]"#, #"["m",7,0]"#])
    }

    func testButtonsKeepTheirOrderWhileABatchIsInFlight() {
        let bridge = makeBridge()
        bridge.handleMove(dx: 5, dy: 0)
        bridge.flush()
        bridge.handleMove(dx: 2, dy: 0)
        bridge.handleButton(0, pressed: true)
        bridge.handleMove(dx: 1, dy: 0)
        bridge.handleButton(0, pressed: false)
        XCTAssertEqual(sent.count, 1)

        completeOldest()
        XCTAssertEqual(sent.last, #"["m",2,0],["b",0,true],["m",1,0],["b",0,false]"#)
    }

    func testAStalledPageDoesNotBlockInputForever() {
        let bridge = makeBridge()
        bridge.handleMove(dx: 1, dy: 0)
        bridge.flush() // never completes
        now = 0.1
        bridge.handleMove(dx: 1, dy: 0)
        bridge.flush()
        XCTAssertEqual(sent.count, 1)

        now = MouseBridge.inFlightTimeout + 0.01
        bridge.flush()
        XCTAssertEqual(sent.count, 2)
    }

    func testAStaleCompletionAfterReLockIsIgnored() {
        let bridge = makeBridge()
        bridge.handleMove(dx: 1, dy: 0)
        bridge.flush()
        bridge.isActive = false
        bridge.isActive = true
        bridge.handleMove(dx: 2, dy: 0)
        bridge.flush() // new lock: not blocked by the old batch
        XCTAssertEqual(sent.count, 2)

        bridge.handleMove(dx: 3, dy: 0)
        completeOldest() // the old batch's completion must not unblock the new one
        bridge.flush()
        XCTAssertEqual(sent.count, 2)
    }
}
