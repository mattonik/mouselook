import SwiftUI

struct ServiceChooserStep: View {
    let services: [ServiceProfile]
    let onChoose: (ServiceProfile) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose your service")
                        .font(.largeTitle.bold())
                    Text("You can change this later in Settings.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)
                ForEach(ServiceCategory.groups(of: services), id: \.category) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.category.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.services, id: \.id) { service in
                            Button { onChoose(service) } label: { ServiceCard(service: service) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Continues to setup for \(service.name)")
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ServiceCard: View {
    let service: ServiceProfile

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(service.artwork.colors.top), Color(service.artwork.colors.bottom)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 80, height: 80)
                .overlay(Image(systemName: service.artwork.symbol).font(.system(size: 32)).foregroundStyle(.white))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.name).font(.title2.bold())
                Text(service.tagline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
