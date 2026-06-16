import SwiftUI

/// About / info screen: app identity, a feature-request contact, the privacy
/// promise, and a friendly footer.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let contactEmail = "matranc03@gmail.com"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        if let url = featureRequestURL { openURL(url) }
                    } label: {
                        HStack {
                            Label("Request a Feature", systemImage: "envelope")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Get in touch")
                } footer: {
                    Text("Opens your mail app to \(contactEmail). Ideas and requests are genuinely welcome.")
                }

                Section("Why it's free") {
                    Text("Scanning a document is about as basic as it gets — tools this basic shouldn't cost you a subscription, bury you in ads, or sell your data. Scanny does one job well, stays free, and keeps your documents on your device. No catch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("No accounts, no ads, no tracking. Everything stays on your device.",
                          systemImage: "lock.shield")
                        .font(.callout)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Made in 🇨🇦 with ❤️")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.23, green: 0.63, blue: 1.0),
                             Color(red: 0.07, green: 0.40, blue: 0.88)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.white))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.18)))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(spacing: 3) {
                Text("Scanny")
                    .font(.title2.weight(.bold))
                Text(versionString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var featureRequestURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = contactEmail
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let body = "\n\n———\nScanny \(version) (\(build))\niOS \(UIDevice.current.systemVersion)"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Scanny Feature Request"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

#Preview {
    AboutView()
}
