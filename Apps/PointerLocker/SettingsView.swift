import SwiftUI

/// ⋯ ▸ Settings…. Values are written to Settings as they change; the
/// browser applies them when the sheet closes (onClose), reloading the page
/// only if the browser identity or debug overlay changed.
struct SettingsView: View {
    let service: ServiceProfile
    let onSwitchService: () -> Void
    let onShowSetupGuide: () -> Void
    let onClose: () -> Void
    let checks: [HealthRow]
    let onCopyDiagnostics: () -> Void

    @State private var sensitivity = Settings.sensitivity
    @State private var invertY = Settings.invertY
    @State private var keepAlive = Settings.backgroundKeepAlive
    @State private var microphone = Settings.microphone
    @State private var useIdentity = Settings.useServiceIdentity
    @State private var debugHUD = Settings.debugHUD
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    LabeledContent(service.category.settingsLabel, value: service.name)
                    if ServiceSwitch.isOffered() {
                        Button("Switch service…", action: onSwitchService)
                    }
                    Button("Show setup guide", action: onShowSetupGuide)
                }
                Section("Mouse") {
                    Picker("Sensitivity", selection: $sensitivity) {
                        ForEach(Settings.sensitivityPresets, id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                    }
                    Toggle("Invert Y-axis", isOn: $invertY)
                }
                if service.category.hasGameSession {
                    Section {
                        Picker("Keep game running in background", selection: $keepAlive) {
                            ForEach(Settings.backgroundKeepAlivePresets, id: \.seconds) { Text($0.title).tag($0.seconds) }
                        }
                        Picker("Microphone", selection: $microphone) {
                            ForEach(MicrophoneAccess.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    } header: {
                        Text("Game session")
                    } footer: {
                        Text("Keeping the game running lets you switch apps briefly without losing your session.")
                    }
                }
                Section {
                    Toggle("Use \(service.name) browser identity", isOn: $useIdentity)
                        .disabled(service.identity == .webKitDefault)
                    Toggle("Debug overlay", isOn: $debugHUD)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Browser identity makes the service see a desktop browser, which the mouse features need. Changes here reload the page.")
                }
                Section {
                    ForEach(checks) { row in
                        LabeledContent(row.title) {
                            switch row.status?.result {
                            case .ok?: Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .problem?: Label("Problem", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            case nil: Text("Not run yet").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(copied ? "Copied" : "Copy diagnostics") {
                        onCopyDiagnostics()
                        copied = true
                    }
                } header: {
                    Text("Service checks")
                } footer: {
                    Text("Mouselook watches for signs that the service changed how it treats this browser. Diagnostics stay on this iPad until you copy them.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
        }
        .onChange(of: sensitivity) { Settings.sensitivity = sensitivity }
        .onChange(of: invertY) { Settings.invertY = invertY }
        .onChange(of: keepAlive) { Settings.backgroundKeepAlive = keepAlive }
        .onChange(of: microphone) { Settings.microphone = microphone }
        .onChange(of: useIdentity) { Settings.useServiceIdentity = useIdentity }
        .onChange(of: debugHUD) { Settings.debugHUD = debugHUD }
        .preferredColorScheme(.dark)
    }
}
