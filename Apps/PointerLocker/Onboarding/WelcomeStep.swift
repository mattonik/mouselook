import SwiftUI

/// When Welcome's two cards stack instead of sitting side by side: only for
/// accessibility text sizes and narrow windows. Measuring whether the text
/// fits on one line (ViewThatFits) stacked them on a full iPad as soon as a
/// summary grew longer than half the width.
enum WelcomeLayout {
    static func stacksCards(dynamicTypeSize: DynamicTypeSize, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact
    }
}

struct WelcomeStep: View {
    let services: [ServiceProfile]
    let onContinue: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                    // Create and Play side by side, stacked when the text is large
                    // or the window narrow. Cards as tall as their text, and as
                    // tall as each other.
                    let layout = WelcomeLayout.stacksCards(dynamicTypeSize: dynamicTypeSize, horizontalSizeClass: horizontalSizeClass)
                        ? AnyLayout(VStackLayout(spacing: 16))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    layout { worldCards }
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
