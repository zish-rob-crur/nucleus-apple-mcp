import SwiftUI
import UIKit

struct ObjectStoreSettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var didLoad = false
    @State private var enabled = false
    @State private var endpoint = ""
    @State private var region = "auto"
    @State private var bucket = ""
    @State private var prefix = ""
    @State private var usePathStyle = true

    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                statusCard
                connectionCard
                credentialsCard

                footer
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NucleusBackground())
        .navigationTitle("Object Store")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadIfNeeded()
        }
    }
}

#Preview {
    NavigationStack {
        ObjectStoreSettingsView()
            .environmentObject(AppModel())
    }
}

private extension ObjectStoreSettingsView {
    var statusCard: some View {
        NucleusCard("Uploads", systemImage: "shippingbox.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("S3-compatible object store")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(summaryLine)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    StatusPill(label: statusLabel, kind: statusKind, systemImage: statusIcon)
                }

                NucleusInset {
                    Toggle(isOn: $enabled) {
                        Text("Upload after Sync")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .tint(NucleusPalette.accent)
                    .onChange(of: enabled) { _, _ in
                        persistSettings()
                    }
                }

                Text("When enabled, Nucleus uploads exported files on each Sync Now run. It preserves the local relative path as the object key.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.testObjectStore()
                } label: {
                    Label(model.isObjectStoreTesting ? "Testing…" : "Test S3 Upload", systemImage: "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .secondary))
                .disabled(model.isObjectStoreTesting || model.resolvedObjectStoreConfig(requireEnabled: false) == nil)

                if let test = model.lastObjectStoreTest {
                    if test.success {
                        NucleusSuccessCallout(message: test.message)
                            .contextMenu {
                                Button("Copy") {
                                    UIPasteboard.general.string = test.message
                                }
                            }
                    } else {
                        NucleusErrorCallout(message: test.message)
                            .contextMenu {
                                Button("Copy") {
                                    UIPasteboard.general.string = test.message
                                }
                            }
                    }
                }
            }
        }
    }

    var connectionCard: some View {
        NucleusCard("Connection", systemImage: "link") {
            VStack(alignment: .leading, spacing: 12) {
                NucleusInset {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Endpoint (e.g. s3.amazonaws.com, <accountid>.r2.cloudflarestorage.com, minio.example.com)", text: $endpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))
                            .onChange(of: endpoint) { _, _ in
                                persistSettings()
                            }

                        HStack(spacing: 10) {
                            TextField("Region (e.g. us-east-1 / auto)", text: $region)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                                .onChange(of: region) { _, _ in
                                    persistSettings()
                                }

                            TextField("Bucket", text: $bucket)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                                .onChange(of: bucket) { _, _ in
                                    persistSettings()
                                }
                        }

                        TextField("Prefix (optional)", text: $prefix)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))
                            .onChange(of: prefix) { _, _ in
                                persistSettings()
                            }

                        Toggle(isOn: $usePathStyle) {
                            Text("Use path-style URLs")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .tint(NucleusPalette.accent)
                        .onChange(of: usePathStyle) { _, _ in
                            persistSettings()
                        }
                    }
                }

                Text("Works with any S3-compatible store that supports SigV4. For Cloudflare R2, use a custom endpoint and typically set region to `auto`. For AWS S3, virtual-hosted style is recommended (toggle off path-style if needed).")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var credentialsCard: some View {
        NucleusCard("Credentials", systemImage: "key.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Stored in Keychain on this device.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)

                    Spacer(minLength: 0)

                    StatusPill(label: model.objectStoreHasCredentials ? "saved" : "missing", kind: model.objectStoreHasCredentials ? .ok : .warning)
                }

                NucleusInset {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Access Key ID", text: $accessKeyId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))

                        SecureField("Secret Access Key", text: $secretAccessKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        saveCredentials()
                    } label: {
                        Label("Save", systemImage: "tray.and.arrow.down.fill")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .secondary))
                    .disabled(!canSaveCredentials)

                    Button {
                        model.clearObjectStoreCredentials()
                        accessKeyId = ""
                        secretAccessKey = ""
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .ghost))
                }
            }
        }
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("For production, prefer short-lived credentials or pre-signed URLs. Long-lived keys in an app are risky.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }

    var summaryLine: String {
        let b = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bucketLabel = b.isEmpty ? "<bucket>" : b
        let location = p.isEmpty ? "s3://\(bucketLabel)/" : "s3://\(bucketLabel)/\(p)/"
        if b.isEmpty { return "Not configured yet." }
        return enabled ? location : "\(location) (uploads off)"
    }

    var statusLabel: String {
        let configured = model.resolvedObjectStoreConfig(requireEnabled: false) != nil
        if configured {
            return enabled ? "Ready" : "Configured"
        }
        return enabled ? "Needs Setup" : "Off"
    }

    var statusKind: StatusPill.Kind {
        let configured = model.resolvedObjectStoreConfig(requireEnabled: false) != nil
        if configured {
            return enabled ? .ok : .neutral
        }
        return enabled ? .warning : .neutral
    }

    var statusIcon: String {
        let configured = model.resolvedObjectStoreConfig(requireEnabled: false) != nil
        if configured {
            return enabled ? "cloud.fill" : "cloud"
        }
        return enabled ? "exclamationmark.triangle.fill" : "cloud.slash"
    }

    var canSaveCredentials: Bool {
        !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !secretAccessKey.isEmpty
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let settings = model.objectStoreSettings
        enabled = settings.enabled
        endpoint = settings.endpoint
        region = settings.region
        bucket = settings.bucket
        prefix = settings.prefix
        usePathStyle = settings.usePathStyle

        if let credentials = ObjectStoreSettingsStore.loadCredentials() {
            accessKeyId = credentials.accessKeyId
        }
    }

    func persistSettings() {
        model.saveObjectStoreSettings(
            ObjectStoreSettings(
                enabled: enabled,
                endpoint: endpoint,
                region: region.trimmingCharacters(in: .whitespacesAndNewlines),
                bucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines),
                prefix: prefix.trimmingCharacters(in: .whitespacesAndNewlines),
                usePathStyle: usePathStyle
            )
        )
    }

    func saveCredentials() {
        let keyId = accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveObjectStoreCredentials(accessKeyId: keyId, secretAccessKey: secretAccessKey)
        secretAccessKey = ""
    }
}
