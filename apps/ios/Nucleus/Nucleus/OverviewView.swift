import SwiftUI
import UIKit

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: RootTab

    @State private var appear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        .scrollIndicators(.hidden)
        .background(NucleusBackground())
        .navigationBarHidden(true)
        .onAppear {
            guard !reduceMotion else {
                appear = true
                return
            }
            withAnimation(.easeOut(duration: 0.85)) {
                appear = true
            }
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
        let accentOpacity: Double = colorScheme == .dark ? 0.12 : 0.04

        return VStack(alignment: .leading, spacing: 10) {
            Text("Nucleus")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
                .tracking(-0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("Local-first personal data exporter")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            headerSummary
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
            if model.orbState != .idle {
                NucleusOrb(state: model.orbState, size: 72)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 8)
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: entryOffset(10))
        .accessibilityElement(children: .combine)
    }

    var headerSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                headerFact(title: "Access", value: healthStatusChip, systemImage: healthStatusIcon, kind: healthStatusKind)
                headerFact(title: "Storage", value: backendChipLabel, systemImage: backendIcon, kind: backendKind)
                headerFact(title: "Upload", value: objectStoreLabel, systemImage: objectStoreIcon, kind: objectStoreKind)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading),
                    GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                headerFact(title: "Access", value: healthStatusChip, systemImage: healthStatusIcon, kind: healthStatusKind)
                headerFact(title: "Storage", value: backendChipLabel, systemImage: backendIcon, kind: backendKind)
                headerFact(title: "Upload", value: objectStoreLabel, systemImage: objectStoreIcon, kind: objectStoreKind)
            }
        }
    }

    var statusCard: some View {
        NucleusCard("Status") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
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

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading),
                        GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    statusDetail(title: "Storage", value: backendLabel)
                    statusDetail(title: "Capture", value: syncModeLabel)
                    statusDetail(title: "Upload", value: objectStoreLabel)
                }

                if let syncModeNote {
                    Text(syncModeNote)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: entryOffset(14))
    }

    var quickActionsCard: some View {
        NucleusCard("Sync", systemImage: "arrow.triangle.2.circlepath") {
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
                    model.beginManualSync()
                    selectedTab = .sync
                } label: {
                    Label(model.manualSyncButtonTitle, systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: model.authRequestStatus == .shouldRequest ? .secondary : .primary))
                .disabled(model.isSyncing || model.isBootstrapping)

                Text(syncSummaryText)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    selectedTab = .settings
                } label: {
                    Label("Configure Storage & Uploads", systemImage: "shippingbox")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .ghost))

                if showsSettingsShortcut {
                    Button {
                        openSettings()
                    } label: {
                        Label("Open iOS Settings", systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .ghost))
                }
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: entryOffset(16))
    }

    var latestWriteCard: some View {
        let snapshot = model.activitySnapshot

        return NucleusCard("Recent Sync", systemImage: "clock.badge.checkmark") {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(activityTitleColor(snapshot.phase))

                Text(snapshot.detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(snapshot.metaLine)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let shortRevision = snapshot.shortRevision {
                    Text("Revision \(shortRevision)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(NucleusPalette.accentForeground(colorScheme))
                }

                HStack(spacing: 10) {
                    Button {
                        selectedTab = .sync
                    } label: {
                        Label("Open Sync", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: snapshot.phase == .ready ? .ghost : .secondary))

                    if let written = model.lastWritten {
                        ShareLink(item: written.dailyURL) {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NucleusButtonStyle(kind: .ghost))
                    }
                }
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: entryOffset(18))
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("Runs privately. Upload is optional.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }

    var backendLabel: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "Private"
        case .localDocuments:
            "Private"
        case nil:
            "Unknown"
        }
    }

    var backendChipLabel: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "Private"
        case .localDocuments:
            "Private"
        case nil:
            "Storage"
        }
    }

    var backendIcon: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "folder.fill"
        case .localDocuments:
            "folder.fill"
        case nil:
            "questionmark.circle.fill"
        }
    }

    var backendKind: StatusPill.Kind {
        switch model.storageStatus?.backend {
        case .icloudDrive: .neutral
        case .localDocuments: .neutral
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
        return model.resolvedObjectStoreConfig() != nil ? .neutral : .warning
    }

    var syncModeLabel: String {
        switch model.anchorDiagnostics.modeLabel {
        case "bootstrap":
            "First export"
        case "partial":
            "Backfill needed"
        default:
            "Incremental"
        }
    }

    var syncModeNote: String? {
        switch model.anchorDiagnostics.modeLabel {
        case "bootstrap":
            "The first export will establish anchors for future incremental syncs."
        case "partial":
            "Some tracked types still need anchors. The next sync will backfill them."
        default:
            nil
        }
    }

    var syncSummaryText: String {
        let storageSummary = "Storage stays private."
        if model.needsInitialSyncRangeSelection {
            return "The first sync will ask how much history to import. \(storageSummary)"
        }
        return "Fallback window \(model.catchUpDays)d. \(storageSummary)"
    }

    var showsSettingsShortcut: Bool {
        model.authRequestStatus != .unnecessary || model.lastError != nil
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

    func entryOffset(_ hiddenOffset: CGFloat) -> CGFloat {
        reduceMotion ? 0 : (appear ? 0 : hiddenOffset)
    }

    @ViewBuilder
    func headerFact(title: String, value: String, systemImage: String, kind: StatusPill.Kind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.secondary)
                .labelStyle(.titleAndIcon)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(factForeground(kind))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func statusDetail(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.secondary)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func factForeground(_ kind: StatusPill.Kind) -> Color {
        switch kind {
        case .ok:
            return NucleusPalette.accentForeground(colorScheme)
        case .neutral:
            return Color.primary.opacity(0.84)
        case .warning:
            return NucleusPalette.warning
        case .error:
            return NucleusPalette.danger
        }
    }

    func activityTitleColor(_ phase: NucleusActivityPhase) -> Color {
        switch phase {
        case .ready:
            return .primary
        case .syncing:
            return NucleusPalette.accentForeground(colorScheme)
        case .needsAuthorization:
            return NucleusPalette.warning
        case .setup:
            return .primary
        case .error:
            return NucleusPalette.danger
        }
    }
}
