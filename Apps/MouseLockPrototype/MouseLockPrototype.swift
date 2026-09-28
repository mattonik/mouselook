//
//  MouseLockPrototype.swift
//
//  STANDALONE PROTOTYPE — validates raw GCMouse delta capture on iPadOS,
//  completely independent of WebKit. This is milestone #1: prove that
//  unbounded, unaccelerated mouse deltas can be captured cleanly before
//  investing in the much larger WebKit build/patch effort.
//
//  WHAT THIS DOES:
//   - Detects mouse/trackpad connect & disconnect (GCMouse via Bluetooth,
//     USB, or a Magic Trackpad/Mouse paired to the iPad)
//   - Reads raw movement deltas (deltaX/deltaY) — NOT cursor position —
//     which is the same primitive the Pointer Lock API needs
//   - Reads left/right/middle button state
//   - Logs everything live so you can visually confirm: does movement
//     stay smooth and unbounded even when your physical mouse would hit
//     a desk edge or you lift/replace it? (unbounded relative movement
//     is the whole point of pointer lock — this proves iPadOS gives you
//     that primitive natively via GameController, independent of Safari)
//
//  WHAT THIS DELIBERATELY DOES NOT DO YET:
//   - Does not hide the system pointer (UIPointerInteraction still shows
//     the OS cursor — suppressing that is a separate, later step)
//   - Does not touch WebKit at all
//   - Does not handle Split View / Stage Manager focus-loss edge cases
//
//  SETUP:
//   1. Run `xcodegen` in the repo root and pick the MouseLockPrototype scheme
//   2. No special entitlements or Info.plist keys are required for
//      GameController mouse input — it's available by default on iPadOS 14+
//   3. Run on a real iPad (simulator does not support GCMouse hardware
//      input) with a Bluetooth/USB mouse or trackpad paired
//

import SwiftUI
import GameController

// MARK: - App entry point

@main
struct MouseLockPrototypeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Observable mouse state

@MainActor
final class MouseCaptureModel: ObservableObject {
    @Published var isConnected = false
    @Published var deviceName = "No mouse connected"
    @Published var lastDeltaX: Float = 0
    @Published var lastDeltaY: Float = 0
    @Published var cumulativeX: Float = 0   // running total — proves movement is unbounded
    @Published var cumulativeY: Float = 0
    @Published var leftButtonDown = false
    @Published var rightButtonDown = false
    @Published var middleButtonDown = false
    @Published var eventCount = 0
    @Published var log: [String] = []

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    init() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCMouseDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mouse = notification.object as? GCMouse else { return }
            self?.attach(to: mouse)
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCMouseDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isConnected = false
            self?.deviceName = "No mouse connected"
            self?.appendLog("Mouse disconnected")
        }

        // In case a mouse is already connected when the view launches
        if let existing = GCMouse.mice().first {
            attach(to: existing)
        }
    }

    deinit {
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
    }

    private func attach(to mouse: GCMouse) {
        isConnected = true
        deviceName = mouse.vendorName ?? "Unknown mouse"
        appendLog("Connected: \(deviceName)")

        guard let mouseInput = mouse.mouseInput else { return }

        // This is the core primitive: raw relative deltas, reported every
        // time the physical mouse moves, with no relationship to any
        // on-screen cursor position and no clamping at screen edges.
        mouseInput.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            Task { @MainActor in
                guard let self else { return }
                self.lastDeltaX = deltaX
                self.lastDeltaY = deltaY
                self.cumulativeX += deltaX
                self.cumulativeY += deltaY
                self.eventCount += 1
            }
        }

        mouseInput.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.leftButtonDown = pressed
                self?.appendLog(pressed ? "Left button down" : "Left button up")
            }
        }

        mouseInput.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.rightButtonDown = pressed
                self?.appendLog(pressed ? "Right button down" : "Right button up")
            }
        }

        mouseInput.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.middleButtonDown = pressed
            }
        }
    }

    private func appendLog(_ message: String) {
        log.append(message)
        if log.count > 50 {
            log.removeFirst(log.count - 50)
        }
    }

    func resetCumulative() {
        cumulativeX = 0
        cumulativeY = 0
        eventCount = 0
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var model = MouseCaptureModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GCMouse Delta Capture Prototype")
                .font(.title2)
                .bold()

            HStack {
                Circle()
                    .fill(model.isConnected ? .green : .red)
                    .frame(width: 12, height: 12)
                Text(model.deviceName)
                    .font(.headline)
            }

            GroupBox("Last frame delta") {
                HStack {
                    Text("dX: \(model.lastDeltaX, specifier: "%.2f")")
                    Spacer()
                    Text("dY: \(model.lastDeltaY, specifier: "%.2f")")
                }
                .font(.system(.body, design: .monospaced))
            }

            GroupBox("Cumulative movement (proves unbounded tracking)") {
                HStack {
                    Text("ΣX: \(model.cumulativeX, specifier: "%.1f")")
                    Spacer()
                    Text("ΣY: \(model.cumulativeY, specifier: "%.1f")")
                }
                .font(.system(.body, design: .monospaced))
                Text("\(model.eventCount) move events received")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                buttonIndicator("L", isDown: model.leftButtonDown)
                buttonIndicator("R", isDown: model.rightButtonDown)
                buttonIndicator("M", isDown: model.middleButtonDown)
                Spacer()
                Button("Reset totals") { model.resetCumulative() }
                    .buttonStyle(.bordered)
            }

            GroupBox("Event log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
            }

            Text("Move a paired Bluetooth/USB mouse or trackpad. Deltas should update smoothly with no jumps or clamping, independent of the system pointer's on-screen position.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func buttonIndicator(_ label: String, isDown: Bool) -> some View {
        Text(label)
            .font(.headline)
            .frame(width: 32, height: 32)
            .background(isDown ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isDown ? .white : .primary)
            .clipShape(Circle())
    }
}
