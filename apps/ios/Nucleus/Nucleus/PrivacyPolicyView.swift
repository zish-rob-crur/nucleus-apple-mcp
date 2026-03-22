import SwiftUI

struct PrivacyPolicyView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                dataCard
                retentionCard
                controlsCard

                footer
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(NucleusBackground())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
            .environmentObject(AppModel())
    }
}

private extension PrivacyPolicyView {
    var summaryCard: some View {
        NucleusCard("Summary", systemImage: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nucleus reads Health data only after you grant HealthKit access. It does not require an account, does not run third-party analytics, and does not use advertising SDKs.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    StatusPill(label: "Private", kind: .ok, systemImage: "lock.fill")
                    StatusPill(label: uploadStatusLabel, kind: uploadStatusKind, systemImage: "shippingbox.fill")
                    StatusPill(label: "No Tracking", kind: .neutral, systemImage: "eye.slash.fill")
                }
            }
        }
    }

    var dataCard: some View {
        NucleusCard("Data Use", systemImage: "heart.text.square.fill") {
            VStack(alignment: .leading, spacing: 12) {
                privacyInset(
                    title: "What Nucleus reads",
                    body: "With your permission, Nucleus reads health and fitness samples needed to build daily summaries and raw export files."
                )

                privacyInset(
                    title: "Where exports live",
                    body: "Exports stay in Nucleus private storage by default. Nucleus keeps a stable folder layout so you can inspect or move files yourself."
                )

                privacyInset(
                    title: "Optional uploads",
                    body: "If you enable S3-compatible uploads, Nucleus sends exported files to the bucket and endpoint you configure. Those files are then governed by your storage provider and bucket settings."
                )
            }
        }
    }

    var retentionCard: some View {
        NucleusCard("Retention", systemImage: "internaldrive") {
            VStack(alignment: .leading, spacing: 12) {
                privacyInset(
                    title: "Private retention",
                    body: "Local export files remain in Nucleus private storage until you delete the app or remove the exported files from the app's storage path."
                )

                privacyInset(
                    title: "Uploaded retention",
                    body: "If you turn on object-store uploads, uploaded files remain in your configured bucket until you remove them from that provider."
                )
            }
        }
    }

    var controlsCard: some View {
        NucleusCard("Controls", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                privacyInset(
                    title: "Health access",
                    body: "You can revoke Health access at any time in the Health app or in iOS Settings."
                )

                privacyInset(
                    title: "Upload credentials",
                    body: "Object-store credentials are stored in Keychain. You can remove them from Nucleus Settings at any time."
                )
            }
        }
    }

    func privacyInset(title: String, body: String) -> some View {
        NucleusInset {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)

                Text(body)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var uploadStatusLabel: String {
        model.objectStoreSettings.enabled ? "Uploads Optional" : "Uploads Off"
    }

    var uploadStatusKind: StatusPill.Kind {
        model.objectStoreSettings.enabled ? .warning : .neutral
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("If you enable uploads, review your object-store provider's privacy, retention, and access policies as well.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }
}
