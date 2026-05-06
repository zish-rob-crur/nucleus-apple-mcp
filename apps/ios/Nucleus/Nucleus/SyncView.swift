import SwiftUI
import UIKit

struct SyncView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: RootTab

    @State private var showExportDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let progress = model.syncProgress {
                    progressCard(progress)
                }

                planCard
                recentExportCard
                highlightsCard

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
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SyncView(selectedTab: .constant(.sync))
            .environmentObject(AppModel())
    }
}

private extension SyncView {
    var header: some View {
        let cornerRadius: CGFloat = 28
        let accentOpacity: Double = colorScheme == .dark ? 0.14 : 0.05

        return VStack(alignment: .leading, spacing: 10) {
            Text("Sync")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
                .tracking(-0.6)

            Text("Keep your export current. Nucleus rewrites only the dates touched by HealthKit changes and can surface progress beyond the app while a sync is active.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                NucleusOrb(state: model.orbState, size: 68)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
    }

    var headerSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                summaryFact(title: "Capture", value: syncModeLabel, systemImage: "bolt.badge.clock", kind: syncModeKind)
                summaryFact(title: "Background", value: backgroundDeliveryLabel, systemImage: "waveform.badge.magnifyingglass", kind: backgroundDeliveryKind)
                summaryFact(title: "Storage", value: backendLabel, systemImage: backendIcon, kind: backendKind)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading),
                    GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                summaryFact(title: "Capture", value: syncModeLabel, systemImage: "bolt.badge.clock", kind: syncModeKind)
                summaryFact(title: "Background", value: backgroundDeliveryLabel, systemImage: "waveform.badge.magnifyingglass", kind: backgroundDeliveryKind)
                summaryFact(title: "Storage", value: backendLabel, systemImage: backendIcon, kind: backendKind)
            }
        }
    }

    func progressCard(_ progress: SyncProgress) -> some View {
        NucleusCard("Now", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 12) {
                SyncProgressPanel(progress: progress)

                Text(progress.supportingNote)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var planCard: some View {
        NucleusCard("Plan", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 12) {
                NucleusInset {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Fallback window")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Used after the first sync when HealthKit reports deletions without enough local context.")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)

                            Text("\(model.catchUpDays)d")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(NucleusPalette.accentForeground(colorScheme))
                        }

                        Stepper(
                            value: Binding(
                                get: { model.catchUpDays },
                                set: { model.setCatchUpDays($0) }
                            ),
                            in: 1...14
                        ) {
                            Text("Adjust window")
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                if model.needsInitialSyncRangeSelection {
                    NucleusInset {
                        Text("The first sync will ask how much history to import before it starts.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    model.beginManualSync()
                } label: {
                    Label(model.manualSyncButtonTitle, systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .primary))
                .disabled(!model.canStartManualSync)

                Button {
                    selectedTab = .settings
                } label: {
                    Label("Configure Storage & Uploads", systemImage: "shippingbox")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .ghost))

                if model.objectStoreSettings.enabled, model.resolvedObjectStoreConfig() == nil {
                    NucleusWarningCallout(message: "Object store is enabled but incomplete. Finish setup in Settings.")
                        .onTapGesture {
                            selectedTab = .settings
                        }
                }

                if let error = model.lastError {
                    NucleusErrorCallout(message: error)
                }
            }
        }
    }

    var recentExportCard: some View {
        let snapshot = model.activitySnapshot

        return NucleusCard("Recent Export", systemImage: "clock.badge.checkmark") {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(activityTitleColor(snapshot.phase))

                Text(snapshot.detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let revision = model.latestRevision {
                    HStack(spacing: 10) {
                        Text(revision.date)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Text(compactTimezone(revision.day.timezone))
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Text(snapshot.metaLine)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let shortRevision = snapshot.shortRevision {
                    Text("Revision \(shortRevision)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(NucleusPalette.accentForeground(colorScheme))
                }

                if let written = model.lastWritten {
                    HStack(spacing: 10) {
                        ShareLink(item: written.dailyURL) {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NucleusButtonStyle(kind: .secondary))

                        Button {
                            selectedTab = .overview
                        } label: {
                            Label("Home", systemImage: "house")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NucleusButtonStyle(kind: .ghost))
                    }

                    NucleusInset {
                        DisclosureGroup(isExpanded: $showExportDetails) {
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

                                HStack(spacing: 10) {
                                    ShareLink(item: written.monthURL) {
                                        Label("Share Month Index", systemImage: "calendar")
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
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Export file details")
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .tint(.primary)
                    }
                } else {
                    Text("Run the first sync to create a recent export.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var highlightsCard: some View {
        NucleusCard("Highlights", systemImage: "heart.text.square") {
            VStack(alignment: .leading, spacing: 12) {
                if let revision = model.latestRevision {
                    Text("From the last synced day, so you can confirm the export still feels current.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(highlightMetricKeys) { key in
                            MetricTile(key: key, result: metricResult(key, revision: revision))
                        }
                    }
                } else {
                    Text("Once a sync completes, this area surfaces a few recent health highlights instead of raw export files.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("Sync runs locally. Upload stays optional, and background delivery keeps incremental syncs lightweight.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }

    var highlightMetricKeys: [MetricKey] {
        [
            .steps,
            .exerciseMinutes,
            .sleepAsleepMinutes,
            .restingHrAvg,
        ]
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
        case .icloudDrive, .localDocuments:
            .neutral
        case nil:
            .error
        }
    }

    var backgroundDeliveryLabel: String {
        switch model.backgroundDeliveryStatus {
        case .idle:
            "Waiting"
        case .needsAuthorization:
            "Needs access"
        case .ready:
            "Background on"
        case .error:
            "Delivery issue"
        }
    }

    var backgroundDeliveryKind: StatusPill.Kind {
        switch model.backgroundDeliveryStatus {
        case .idle:
            .neutral
        case .needsAuthorization:
            .warning
        case .ready:
            .ok
        case .error:
            .error
        }
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
            "Backfill"
        default:
            "Incremental"
        }
    }

    var syncModeKind: StatusPill.Kind {
        model.anchorDiagnostics.unprimedTypeKeys.isEmpty ? .ok : .warning
    }

    func metricResult(_ key: MetricKey, revision: DailyRevision) -> MetricResult {
        let status = revision.metricStatus[key.rawValue] ?? .no_data
        let unit = revision.metricUnits[key.rawValue] ?? key.unitString
        let value = revision.metrics[key.rawValue] ?? nil
        return MetricResult(value: value ?? nil, status: status, unit: unit)
    }

    func compactTimezone(_ identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    @ViewBuilder
    func summaryFact(title: String, value: String, systemImage: String, kind: StatusPill.Kind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.secondary)
                .labelStyle(.titleAndIcon)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(summaryForeground(kind))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func summaryForeground(_ kind: StatusPill.Kind) -> Color {
        switch kind {
        case .ok:
            NucleusPalette.accentForeground(colorScheme)
        case .neutral:
            Color.primary.opacity(0.84)
        case .warning:
            NucleusPalette.warning
        case .error:
            NucleusPalette.danger
        }
    }

    func activityTitleColor(_ phase: NucleusActivityPhase) -> Color {
        switch phase {
        case .ready:
            .primary
        case .syncing:
            NucleusPalette.accentForeground(colorScheme)
        case .needsAuthorization:
            NucleusPalette.warning
        case .setup:
            .primary
        case .error:
            NucleusPalette.danger
        }
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

private struct MetricTile: View {
    let key: MetricKey
    let result: MetricResult
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))

                    Circle()
                        .stroke(tint.opacity(0.18), lineWidth: 1)

                    Image(systemName: key.systemImage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                }
                .frame(width: 30, height: 30)

                Text(key.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                StatusPill(label: statusLabel, kind: kind)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(result.unit.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(14)
        .background(NucleusTileBackground(tint: tint))
    }

    private var kind: StatusPill.Kind {
        switch result.status {
        case .ok: .ok
        case .no_data: .neutral
        case .unauthorized: .warning
        case .unsupported: .error
        }
    }

    private var statusLabel: String {
        switch result.status {
        case .ok:
            "Ready"
        case .no_data:
            "No data"
        case .unauthorized:
            "Access"
        case .unsupported:
            "Unsupported"
        }
    }

    private var valueText: String {
        guard result.status == .ok, let value = result.value else { return "—" }

        switch key {
        case .steps, .exerciseMinutes, .standHours, .sleepAsleepMinutes, .sleepInBedMinutes:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .activeEnergyKcal:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .restingHrAvg:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .hrvSdnnAvg:
            return value.formatted(.number.precision(.fractionLength(0...1)))
        case .vo2Max:
            return value.formatted(.number.precision(.fractionLength(1)))
        case .oxygenSaturationPct, .bodyFatPercentage:
            return value.formatted(.number.precision(.fractionLength(1)))
        case .respiratoryRateAvg:
            return value.formatted(.number.precision(.fractionLength(1)))
        case .wristTemperatureCelsius, .bodyTemperatureCelsius, .basalBodyTemperatureCelsius:
            return value.formatted(.number.precision(.fractionLength(1)))
        case .bodyMassKg:
            return value.formatted(.number.precision(.fractionLength(1)))
        case .bloodPressureSystolicMmhg, .bloodPressureDiastolicMmhg:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .bloodGlucoseMgDl:
            return value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    private var valueColor: Color {
        switch result.status {
        case .ok:
            NucleusPalette.accentForeground(colorScheme)
        case .no_data:
            Color.secondary
        case .unauthorized:
            NucleusPalette.warning
        case .unsupported:
            NucleusPalette.danger
        }
    }

    private var tint: Color {
        switch result.status {
        case .ok:
            NucleusPalette.accent
        case .no_data:
            Color.secondary.opacity(0.55)
        case .unauthorized:
            NucleusPalette.warning
        case .unsupported:
            NucleusPalette.danger
        }
    }
}
