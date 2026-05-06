import SwiftUI
import UIKit

struct StorageSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                storageCard

                if let status = model.storageStatus {
                    pathCard(status: status)
                }

                footer
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, NucleusStyle.floatingTabBarClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(NucleusBackground())
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.refreshStorageStatus(preferICloud: false)
        }
    }
}

#Preview {
    NavigationStack {
        StorageSettingsView()
            .environmentObject(AppModel())
    }
}

private extension StorageSettingsView {
    var storageCard: some View {
        NucleusCard("Storage", systemImage: "externaldrive.fill") {
            VStack(alignment: .leading, spacing: 12) {
                NucleusInset {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Private export")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Nucleus keeps Health exports in private app storage. The folder layout still matches object-store uploads.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("Export paths remain stable: `health/daily`, `health/raw`, and `health/commits`.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func pathCard(status: StorageStatus) -> some View {
        NucleusCard("Export Path", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatusPill(label: status.backendLabel, kind: .ok)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = status.rootURL.path(percentEncoded: false)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .ghost))
                }

                Text(status.locationSummary)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Layout: health/daily, health/raw, health/commits. The relative paths match the S3 object keys.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(status.rootURL.path(percentEncoded: false))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "internaldrive")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("If you need files outside Nucleus private storage, use the object-store export path instead of app-managed cloud storage.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }
}

private extension StorageStatus {
    var backendLabel: String {
        switch backend {
        case .icloudDrive:
            "Private"
        case .localDocuments:
            "Private"
        }
    }

    var locationSummary: String {
        switch backend {
        case .icloudDrive:
            "Stored in Nucleus private storage"
        case .localDocuments:
            "Stored in Nucleus private storage"
        }
    }
}
