import SwiftUI
import UIKit

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: RootTab

    @State private var appear = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                statusCard
                quickActionsCard

                if let error = model.lastError {
                    NucleusErrorCallout(message: error)
                }

                latestWriteCard

                footer
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NucleusBackground())
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) {
                appear = true
            }
        }
        .task {
            await model.refreshAuthStatus()
            await model.refreshAnchorDiagnostics()
            model.refreshStorageStatus(preferICloud: model.preferICloud)
        }
    }
}

#Preview {
    NavigationStack {
        OverviewView(selectedTab: .constant(.overview))
            .environmentObject(AppModel())
    }
}

private extension OverviewView {
    var header: some View {
        let cornerRadius: CGFloat = 28
        let accentOpacity: Double = colorScheme == .dark ? 0.20 : 0.10

        return VStack(alignment: .leading, spacing: 12) {
            Text("Nucleus")
                .font(.system(size: 46, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
                .tracking(-0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("Local-first personal data exporter")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            headerChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            NucleusCardBackground(cornerRadius: cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    NucleusPalette.accent.opacity(accentOpacity),
                                    .clear,
                                ],
                                center: .topTrailing,
                                startRadius: 12,
                                endRadius: 420
                            )
                        )
                        .blendMode(colorScheme == .dark ? .plusLighter : .screen)
                )
        }
        .overlay(alignment: .topTrailing) {
            NucleusOrb(state: model.orbState, size: 84)
                .padding(.top, 14)
                .padding(.trailing, 14)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .accessibilityElement(children: .combine)
    }

    var headerChips: some View {
                HStack(spacing: 10) {
                    StatusPill(label: healthStatusChip, kind: healthStatusKind, systemImage: healthStatusIcon)
                    StatusPill(label: model.anchorDiagnostics.modeLabel, kind: model.anchorDiagnostics.unprimedTypeKeys.isEmpty ? .ok : .warning, systemImage: "bolt.badge.clock")
                    StatusPill(label: backendChipLabel, kind: backendKind, systemImage: backendIcon)
                    StatusPill(label: objectStoreLabel, kind: objectStoreKind, systemImage: objectStoreIcon)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
    }

    var statusCard: some View {
        NucleusCard("Status", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(healthStatusTitle)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(healthStatusDescription)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    StatusPill(label: healthStatusChip, kind: healthStatusKind, systemImage: healthStatusIcon)
                }

                Divider()
                    .overlay(Color.primary.opacity(0.10))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.secondary)
                        Text(backendLabel)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Object store")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.secondary)
                        Text(objectStoreLabel)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 14)
    }

    var quickActionsCard: some View {
        NucleusCard("Actions", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if model.authRequestStatus == .shouldRequest {
                    Button {
                        model.requestHealthAuthorization()
                    } label: {
                        Label(model.isAuthorizing ? "Authorizing…" : "Request Health Access", systemImage: "heart.text.square")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .primary))
                    .disabled(model.isAuthorizing)
                }

                Button {
                    model.syncNow(catchUpDays: model.catchUpDays)
                    selectedTab = .sync
                } label: {
                    Label(model.isSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .secondary))
                .disabled(model.isSyncing)

                HStack(spacing: 10) {
                    NucleusInlineStat(title: "Window", value: "\(model.catchUpDays)d")
                    NucleusInlineStat(title: "iCloud", value: model.preferICloud ? "preferred" : "off")
                }

                Button {
                    openSettings()
                } label: {
                    Label("Open iOS Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .ghost))

                Button {
                    selectedTab = .settings
                } label: {
                    Label("Configure Storage & Uploads", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .ghost))
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 16)
    }

    var latestWriteCard: some View {
        NucleusCard("Latest", systemImage: "clock") {
            VStack(alignment: .leading, spacing: 12) {
                if let written = model.lastWritten {
                    HStack(spacing: 10) {
                        Text(written.revisionId)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(NucleusPalette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 0)

                        StatusPill(label: "snapshot", kind: .neutral)
                    }

                    if let revision = model.latestRevision {
                        Text(revision.date)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Text("Saved to \(backendLabel)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.secondary)

                    NucleusInset {
                        VStack(alignment: .leading, spacing: 10) {
                            fileLine(
                                title: "Summary",
                                fileName: written.dailyURL.lastPathComponent,
                                pathToCopy: written.dailyURL.path(percentEncoded: false)
                            )

                            fileLine(
                                title: "Month",
                                fileName: written.monthURL.lastPathComponent,
                                pathToCopy: written.monthURL.path(percentEncoded: false)
                            )

                            if let rawWritten = model.lastRawWritten {
                                fileLine(
                                    title: "Raw",
                                    fileName: rawWritten.manifestURL.lastPathComponent,
                                    pathToCopy: rawWritten.manifestURL.path(percentEncoded: false)
                                )
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        ShareLink(item: written.dailyURL) {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NucleusButtonStyle(kind: .ghost))

                        if let rawWritten = model.lastRawWritten {
                            ShareLink(item: rawWritten.manifestURL) {
                                Label("Share Raw Manifest", systemImage: "doc.plaintext")
                                    .labelStyle(.titleAndIcon)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NucleusButtonStyle(kind: .ghost))
                        }
                    }
                } else {
                    Text("No exports yet. Run Sync Now to generate the first revision.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 18)
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("Runs locally. Writes to your private storage. Upload is optional.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }

    var backendLabel: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "iCloud Drive"
        case .localDocuments:
            "Local Documents"
        case nil:
            "Unknown"
        }
    }

    var backendChipLabel: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "iCloud"
        case .localDocuments:
            "Local"
        case nil:
            "Storage"
        }
    }

    var backendIcon: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "icloud"
        case .localDocuments:
            "folder.fill"
        case nil:
            "questionmark.circle.fill"
        }
    }

    var backendKind: StatusPill.Kind {
        switch model.storageStatus?.backend {
        case .icloudDrive: .ok
        case .localDocuments: .warning
        case nil: .error
        }
    }

    var objectStoreLabel: String {
        model.objectStoreSettings.enabled ? "S3 On" : "S3 Off"
    }

    var objectStoreIcon: String {
        model.objectStoreSettings.enabled ? "shippingbox.fill" : "shippingbox"
    }

    var objectStoreKind: StatusPill.Kind {
        if !model.objectStoreSettings.enabled { return .neutral }
        return model.resolvedObjectStoreConfig() != nil ? .ok : .warning
    }

    var healthStatusTitle: String {
        switch model.authRequestStatus {
        case .unnecessary:
            "Ready"
        case .shouldRequest:
            "Needs HealthKit access"
        case .unknown:
            "HealthKit status unknown"
        @unknown default:
            "HealthKit status unknown"
        }
    }

    var healthStatusDescription: String {
        switch model.authRequestStatus {
        case .shouldRequest:
            "Not authorized. Nucleus needs read access per type to export data."
        case .unnecessary:
            "Permissions have been set. If metrics are missing, review per-type access in Settings."
        case .unknown:
            "HealthKit status unknown (or not available)."
        @unknown default:
            "HealthKit status unknown."
        }
    }

    var healthStatusChip: String {
        switch model.authRequestStatus {
        case .shouldRequest: "Access"
        case .unnecessary: "Ready"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }

    var healthStatusIcon: String {
        switch model.authRequestStatus {
        case .unnecessary:
            "checkmark.seal.fill"
        case .shouldRequest:
            "hand.raised.fill"
        case .unknown:
            "questionmark.circle.fill"
        @unknown default:
            "questionmark.circle.fill"
        }
    }

    var healthStatusKind: StatusPill.Kind {
        switch model.authRequestStatus {
        case .unnecessary: .ok
        case .shouldRequest: .warning
        case .unknown: .neutral
        @unknown default: .neutral
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    @ViewBuilder
    func fileLine(title: String, fileName: String, pathToCopy: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 70, alignment: .leading)

            Text(fileName)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contextMenu {
                    Button("Copy Path") { UIPasteboard.general.string = pathToCopy }
                    Button("Copy Name") { UIPasteboard.general.string = fileName }
                }

            Spacer(minLength: 0)
        }
    }
}
