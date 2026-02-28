import SwiftUI
import UIKit

struct StorageSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
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
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NucleusBackground())
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.refreshStorageStatus(preferICloud: model.preferICloud)
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
        NucleusCard("Backend", systemImage: "externaldrive.fill") {
            VStack(alignment: .leading, spacing: 12) {
                NucleusInset {
                    Toggle(isOn: Binding(
                        get: { model.preferICloud },
                        set: { model.setPreferICloud($0) }
                    )) {
                        Text("Prefer iCloud Drive")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .tint(NucleusPalette.accent)
                }

                Text("If iCloud Drive is available, Nucleus writes to the app’s iCloud Documents folder; otherwise it falls back to local Documents.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func pathCard(status: StorageStatus) -> some View {
        NucleusCard("Resolved Path", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatusPill(label: status.backend.rawValue, kind: status.backend == .icloudDrive ? .ok : .warning)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = status.rootURL.path(percentEncoded: false)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .ghost))
                }

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
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("iCloud sync timing is controlled by the system. For deterministic testing, use local Documents or Share the exported files.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }
}

