import SwiftUI

struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("PointerLocker")
                .font(.largeTitle.bold())
            Text("Play cloud games with a mouse and keyboard. The mouse locks to the game, the same as on a PC.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Spacer()
            Button(action: onContinue) {
                Text("Get started").frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
