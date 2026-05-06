import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                nextStepCard
                setupCard
                dataSection
                operationsSection
                footer
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, NucleusStyle.floatingTabBarClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(NucleusBackground())
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
                .tracking(-0.6)
                .lineLimit(1)

            Text("Control how Nucleus stores, uploads, and syncs your Health archive.")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                StatusPill(label: healthStatusLabel, kind: healthStatusKind, systemImage: healthStatusIcon)
                StatusPill(label: storageChipLabel, kind: storageChipKind, systemImage: storageChipIcon)
                StatusPill(label: objectStoreChipLabel, kind: objectStoreChipKind, systemImage: objectStoreChipIcon)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    var nextStepCard: some View {
        NucleusCard("Next Step", systemImage: nextStepIcon) {
            VStack(alignment: .leading, spacing: 12) {
                Text(nextStepTitle)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(nextStepDetail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                nextStepAction
            }
        }
    }

    @ViewBuilder
    var nextStepAction: some View {
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
        } else if model.objectStoreSettings.enabled, model.resolvedObjectStoreConfig() == nil {
            NavigationLink {
                ObjectStoreSettingsView()
            } label: {
                Label("Finish Upload Setup", systemImage: "shippingbox.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NucleusButtonStyle(kind: .primary))
        } else if model.needsInitialSyncRangeSelection || model.isSyncPausedForNetwork {
            NavigationLink {
                SyncSettingsView()
            } label: {
                Label(model.isSyncPausedForNetwork ? "Review Network Policy" : "Choose First Sync Range", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NucleusButtonStyle(kind: .primary))
        } else if model.lastError != nil {
            NavigationLink {
                DiagnosticsView()
            } label: {
                Label("Open Diagnostics", systemImage: "stethoscope")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NucleusButtonStyle(kind: .secondary))
        } else {
            NavigationLink {
                SyncSettingsView()
            } label: {
                Label("Review Sync Policy", systemImage: "wifi")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NucleusButtonStyle(kind: .secondary))
        }
    }

    var setupCard: some View {
        NucleusCard("Current Setup", systemImage: "slider.horizontal.3") {
            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                summaryTile(title: "Access", value: healthStatusLabel, systemImage: healthStatusIcon, kind: healthStatusKind)
                summaryTile(title: "Storage", value: storageChipLabel, systemImage: storageChipIcon, kind: storageChipKind)
                summaryTile(title: "Uploads", value: objectStoreChipLabel, systemImage: objectStoreChipIcon, kind: objectStoreChipKind)
                summaryTile(title: "Network", value: networkPolicyShortLabel, systemImage: networkIcon, kind: networkStatusKind)
            }
        }
    }

    var dataSection: some View {
        NucleusCard("Data", systemImage: "folder.badge.gearshape") {
            VStack(spacing: 10) {
                settingsRow(
                    title: "Storage",
                    subtitle: storageSubtitle,
                    systemImage: "externaldrive.fill",
                    badgeLabel: storageChipLabel,
                    badgeKind: storageChipKind,
                    badgeIcon: storageChipIcon
                ) {
                    StorageSettingsView()
                }

                settingsRow(
                    title: "Uploads",
                    subtitle: objectStoreSubtitle,
                    systemImage: "shippingbox.fill",
                    badgeLabel: objectStoreChipLabel,
                    badgeKind: objectStoreChipKind,
                    badgeIcon: objectStoreChipIcon
                ) {
                    ObjectStoreSettingsView()
                }

                settingsRow(
                    title: "Privacy",
                    subtitle: "Review what stays local and what can leave the device.",
                    systemImage: "hand.raised.fill",
                    badgeLabel: "Private",
                    badgeKind: .ok,
                    badgeIcon: "lock.fill"
                ) {
                    PrivacyPolicyView()
                }
            }
        }
    }

    var operationsSection: some View {
        NucleusCard("Operations", systemImage: "waveform.path.ecg") {
            VStack(spacing: 10) {
                settingsRow(
                    title: "Sync",
                    subtitle: syncSubtitle,
                    systemImage: "arrow.triangle.2.circlepath",
                    badgeLabel: syncBadgeLabel,
                    badgeKind: syncBadgeKind,
                    badgeIcon: syncBadgeIcon
                ) {
                    SyncSettingsView()
                }

                settingsRow(
                    title: "Diagnostics",
                    subtitle: diagnosticsSubtitle,
                    systemImage: "stethoscope",
                    badgeLabel: diagnosticsBadgeLabel,
                    badgeKind: diagnosticsBadgeKind,
                    badgeIcon: diagnosticsBadgeIcon
                ) {
                    DiagnosticsView()
                }
            }
        }
    }

    func settingsRow<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        badgeLabel: String,
        badgeKind: StatusPill.Kind,
        badgeIcon: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            NucleusInset {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: systemImage)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(NucleusPalette.accentForeground(colorScheme))
                            .frame(width: 26)

                        Text(title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        StatusPill(label: badgeLabel, kind: badgeKind, systemImage: badgeIcon)

                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                    }

                    Text(subtitle)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 38)
                }
            }
        }
        .buttonStyle(.plain)
    }

    func summaryTile(title: String, value: String, systemImage: String, kind: StatusPill.Kind) -> some View {
        NucleusInset {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .labelStyle(.titleAndIcon)

                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(summaryForeground(kind))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
    }

    var summaryColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), spacing: 10, alignment: .leading),
            GridItem(.flexible(minimum: 120), spacing: 10, alignment: .leading),
        ]
    }

    var storageSubtitle: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "Private app storage is ready for local Health exports."
        case .localDocuments:
            "Private app storage is ready for local Health exports."
        case nil:
            "Storage is unavailable. Exports cannot be written yet."
        }
    }

    var objectStoreSubtitle: String {
        if !model.objectStoreSettings.enabled {
            return "Optional S3-compatible uploads are off."
        }
        if model.resolvedObjectStoreConfig() != nil {
            return "Uploads are configured and can run after sync."
        }
        return "Uploads are enabled but endpoint, bucket, or credentials need attention."
    }

    var diagnosticsSubtitle: String {
        if let error = model.lastError {
            return "Last error: \(error)"
        }
        return model.logs.isEmpty ? "No logs yet" : "\(model.logs.count) log lines"
    }

    var syncSubtitle: String {
        if model.isSyncing {
            return model.syncProgress?.detail ?? "Sync in progress"
        }
        if model.isSyncPausedForNetwork {
            return model.networkSyncDetail
        }
        if model.needsInitialSyncRangeSelection {
            return "Choose first import range"
        }
        return "Fallback window \(model.catchUpDays)d. \(model.networkSyncPolicyLabel)."
    }

    var nextStepTitle: String {
        if model.authRequestStatus == .shouldRequest {
            return "Grant Health access"
        }
        if model.objectStoreSettings.enabled, model.resolvedObjectStoreConfig() == nil {
            return "Finish upload setup"
        }
        if model.isSyncPausedForNetwork {
            return "Sync is waiting on network"
        }
        if model.needsInitialSyncRangeSelection {
            return "Choose first sync range"
        }
        if model.lastError != nil {
            return "Review diagnostics"
        }
        return "Configuration looks ready"
    }

    var nextStepDetail: String {
        if model.authRequestStatus == .shouldRequest {
            return "Nucleus cannot export Health data until the app has read permission."
        }
        if model.objectStoreSettings.enabled, model.resolvedObjectStoreConfig() == nil {
            return "Uploads are enabled, but the object store is missing a valid endpoint, bucket, or credentials."
        }
        if model.isSyncPausedForNetwork {
            return model.networkSyncDetail
        }
        if model.needsInitialSyncRangeSelection {
            return "The first sync needs an import window before incremental exports can begin."
        }
        if let error = model.lastError {
            return error
        }
        return "Local exports are private by default. Review sync policy when your network or upload preference changes."
    }

    var nextStepIcon: String {
        if model.authRequestStatus == .shouldRequest {
            return "heart.text.square"
        }
        if model.objectStoreSettings.enabled, model.resolvedObjectStoreConfig() == nil {
            return "shippingbox.fill"
        }
        if model.isSyncPausedForNetwork {
            return "wifi.exclamationmark"
        }
        if model.needsInitialSyncRangeSelection {
            return "calendar.badge.clock"
        }
        if model.lastError != nil {
            return "stethoscope"
        }
        return "checkmark.seal"
    }

    var healthStatusLabel: String {
        switch model.authRequestStatus {
        case .shouldRequest:
            "Needs Access"
        case .unnecessary:
            "Ready"
        case .unknown:
            "Unknown"
        @unknown default:
            "Unknown"
        }
    }

    var healthStatusIcon: String {
        switch model.authRequestStatus {
        case .shouldRequest:
            "hand.raised.fill"
        case .unnecessary:
            "checkmark.seal.fill"
        case .unknown:
            "questionmark.circle.fill"
        @unknown default:
            "questionmark.circle.fill"
        }
    }

    var healthStatusKind: StatusPill.Kind {
        switch model.authRequestStatus {
        case .shouldRequest:
            .warning
        case .unnecessary:
            .ok
        case .unknown:
            .neutral
        @unknown default:
            .neutral
        }
    }

    var storageChipLabel: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "Private"
        case .localDocuments:
            "Private"
        case nil:
            "Unknown"
        }
    }

    var storageChipIcon: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "folder.fill"
        case .localDocuments:
            "folder.fill"
        case nil:
            "questionmark.circle.fill"
        }
    }

    var storageChipKind: StatusPill.Kind {
        switch model.storageStatus?.backend {
        case .icloudDrive: .ok
        case .localDocuments: .ok
        case nil: .error
        }
    }

    var objectStoreChipLabel: String {
        if !model.objectStoreSettings.enabled { return "S3 Off" }
        return model.resolvedObjectStoreConfig() != nil ? "S3 Ready" : "S3 Setup"
    }

    var objectStoreChipIcon: String {
        model.objectStoreSettings.enabled ? "shippingbox.fill" : "shippingbox"
    }

    var objectStoreChipKind: StatusPill.Kind {
        if !model.objectStoreSettings.enabled { return .neutral }
        return model.resolvedObjectStoreConfig() != nil ? .ok : .warning
    }

    var networkPolicyShortLabel: String {
        model.allowCellularSync ? "Wi-Fi + Data" : "Wi-Fi Only"
    }

    var networkIcon: String {
        switch model.networkSyncStatus {
        case .wifi:
            "wifi"
        case .cellular:
            "antenna.radiowaves.left.and.right"
        case .unavailable:
            "wifi.slash"
        case .unknown:
            "wifi.exclamationmark"
        case .other:
            "network"
        }
    }

    var networkStatusKind: StatusPill.Kind {
        switch model.networkSyncStatus {
        case .wifi:
            .ok
        case .cellular:
            model.allowCellularSync ? .ok : .warning
        case .unavailable:
            .warning
        case .unknown:
            .neutral
        case .other:
            .ok
        }
    }

    var syncBadgeLabel: String {
        if model.isSyncing {
            return model.syncProgress?.phaseLabel ?? "syncing"
        }
        if model.isSyncPausedForNetwork {
            return model.allowCellularSync ? "Network" : "Wi-Fi"
        }
        if model.needsInitialSyncRangeSelection {
            return "First Sync"
        }
        return model.anchorDiagnostics.modeLabel
    }

    var syncBadgeIcon: String {
        if model.isSyncing {
            return model.syncProgress?.phaseIcon ?? "arrow.triangle.2.circlepath"
        }
        if model.isSyncPausedForNetwork {
            return networkIcon
        }
        if model.needsInitialSyncRangeSelection {
            return "calendar.badge.clock"
        }
        return "bolt.badge.clock"
    }

    var syncBadgeKind: StatusPill.Kind {
        if model.isSyncing { return .neutral }
        if model.isSyncPausedForNetwork { return .warning }
        return model.anchorDiagnostics.unprimedTypeKeys.isEmpty ? .ok : .warning
    }

    var diagnosticsBadgeLabel: String {
        if model.lastError != nil {
            return "Issue"
        }
        return model.logs.isEmpty ? "Quiet" : "\(model.logs.count)"
    }

    var diagnosticsBadgeIcon: String {
        model.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle.fill"
    }

    var diagnosticsBadgeKind: StatusPill.Kind {
        model.lastError == nil ? .ok : .error
    }

    func summaryForeground(_ kind: StatusPill.Kind) -> Color {
        switch kind {
        case .ok:
            NucleusPalette.accentForeground(colorScheme)
        case .neutral:
            Color.primary.opacity(0.82)
        case .warning:
            NucleusPalette.warning
        case .error:
            NucleusPalette.danger
        }
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("Credentials are stored in Keychain.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }
}
