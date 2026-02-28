import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                NavigationLink {
                    StorageSettingsView()
                } label: {
                    settingsCard(
                        title: "Storage",
                        subtitle: storageSubtitle,
                        systemImage: "externaldrive.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ObjectStoreSettingsView()
                } label: {
                    settingsCard(
                        title: "Object Store",
                        subtitle: objectStoreSubtitle,
                        systemImage: "shippingbox.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DiagnosticsView()
                } label: {
                    settingsCard(
                        title: "Diagnostics",
                        subtitle: diagnosticsSubtitle,
                        systemImage: "stethoscope"
                    )
                }
                .buttonStyle(.plain)

                footer
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NucleusBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AppModel())
    }
}

private extension SettingsView {
    var header: some View {
        NucleusCard("Configuration", systemImage: "gearshape") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep the Home screen focused. Configure storage, S3-compatible uploads, and diagnostics here.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    StatusPill(label: storageChipLabel, kind: storageChipKind, systemImage: storageChipIcon)
                    StatusPill(label: objectStoreChipLabel, kind: objectStoreChipKind, systemImage: objectStoreChipIcon)
                }
            }
        }
    }

    func settingsCard(title: String, subtitle: String, systemImage: String) -> some View {
        NucleusCard(title, systemImage: systemImage) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
    }

    var storageSubtitle: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "iCloud Drive (Documents)"
        case .localDocuments:
            "Local Documents (no iCloud)"
        case nil:
            "Storage unavailable"
        }
    }

    var objectStoreSubtitle: String {
        if !model.objectStoreSettings.enabled { return "Uploads disabled" }
        return model.resolvedObjectStoreConfig() != nil ? "Ready to upload" : "Needs setup"
    }

    var diagnosticsSubtitle: String {
        if let error = model.lastError {
            return "Last error: \(error)"
        }
        return model.logs.isEmpty ? "No logs yet" : "\(model.logs.count) log lines"
    }

    var storageChipLabel: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "icloud"
        case .localDocuments:
            "local"
        case nil:
            "unknown"
        }
    }

    var storageChipIcon: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "icloud"
        case .localDocuments:
            "folder.fill"
        case nil:
            "questionmark.circle.fill"
        }
    }

    var storageChipKind: StatusPill.Kind {
        switch model.storageStatus?.backend {
        case .icloudDrive: .ok
        case .localDocuments: .warning
        case nil: .error
        }
    }

    var objectStoreChipLabel: String {
        if !model.objectStoreSettings.enabled { return "s3 off" }
        return model.resolvedObjectStoreConfig() != nil ? "s3 ready" : "s3 setup"
    }

    var objectStoreChipIcon: String {
        model.objectStoreSettings.enabled ? "shippingbox.fill" : "shippingbox"
    }

    var objectStoreChipKind: StatusPill.Kind {
        if !model.objectStoreSettings.enabled { return .neutral }
        return model.resolvedObjectStoreConfig() != nil ? .ok : .warning
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("Credentials are stored in Keychain on this device and are not synced via iCloud.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }
}
