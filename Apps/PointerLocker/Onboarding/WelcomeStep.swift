import SwiftUI

struct WelcomeStep: View {
    let services: [ServiceProfile]
    let onContinue: () -> Void

    var body: some View {
        // Scrolls when the text doesn't fit (a small window at a large text
        // size); Get started stays pinned at the bottom.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    // The app icon itself, so Welcome matches the home screen.
                    Image("WelcomeIcon")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Mouselook")
                        .font(.largeTitle.bold())
                    Text("A real mouse and keyboard for the web on iPad. The pointer locks the same as on a computer.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                    // Play and Create side by side, stacked when the text is large.
                    // Cards as tall as their text, and as tall as each other.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) { worldCards }
                        VStack(spacing: 16) { worldCards }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640)
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
            // Same black as the page: hides what scrolls underneath without a visible bar.
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder private var worldCards: some View {
        ForEach(ServiceCategory.allCases, id: \.self) { category in
            WorldCard(category: category, services: category.serviceNames(in: services))
        }
    }
}

/// One world on Welcome: what the mouse does there and which services it
/// covers. Explanation only; the service is chosen on the next screen.
private struct WorldCard: View {
    let category: ServiceCategory
    let services: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: category.symbol)
                .font(.title2)
                .foregroundStyle(category == .play ? Color.cyan : Color.purple)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(category.title).font(.headline)
            Text(category.summary).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(services).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
