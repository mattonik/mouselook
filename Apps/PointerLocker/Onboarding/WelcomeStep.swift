import SwiftUI

struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        // Scrolls when the text doesn't fit (a small window at a large text
        // size); Get started stays pinned at the bottom.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Mouselook")
                        .font(.largeTitle.bold())
                    Text("Use a mouse and keyboard in cloud games and web apps. The pointer locks the same as on a computer.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Get started").frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }
}
