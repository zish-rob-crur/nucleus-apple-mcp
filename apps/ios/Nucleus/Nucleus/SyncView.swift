import SwiftUI
import UIKit

struct SyncView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: RootTab

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                controlsCard
                outputsCard
                telemetryCard

                footer
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NucleusBackground())
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refreshAuthStatus()
        }
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
        NucleusCard("Sync", systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Export daily aggregates (v0) + raw samples (v1 JSONL), then optionally upload to your S3-compatible object store.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    StatusPill(label: backendLabel, kind: backendKind, systemImage: backendIcon)
                    StatusPill(label: objectStoreLabel, kind: objectStoreKind, systemImage: objectStoreIcon)
                }
            }
        }
    }

    var controlsCard: some View {
        NucleusCard("Controls", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                NucleusInset {
                    Stepper(value: Binding(
                        get: { model.catchUpDays },
                        set: { model.setCatchUpDays($0) }
                    ), in: 1...14) {
                        HStack {
                            Text("Catch-up window")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Text("\(model.catchUpDays)d")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                Button {
                    model.syncNow(catchUpDays: model.catchUpDays)
                } label: {
                    Label(model.isSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NucleusButtonStyle(kind: .primary))
                .disabled(model.isSyncing)

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

    var outputsCard: some View {
        NucleusCard("Outputs", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                if let written = model.lastWritten {
                    HStack(spacing: 10) {
                        Text(written.revisionId)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(NucleusPalette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 0)

                        StatusPill(label: "latest.json", kind: .neutral)
                    }

                    let revisionPath = written.revisionURL.path(percentEncoded: false)
                    Text(revisionPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                        .contextMenu {
                            Button("Copy") { UIPasteboard.general.string = revisionPath }
                        }

                    HStack(spacing: 10) {
                        ShareLink(item: written.revisionURL) {
                            Label("Share JSON", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NucleusButtonStyle(kind: .secondary))

                        ShareLink(item: written.latestURL) {
                            Label("Share latest.json", systemImage: "link")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NucleusButtonStyle(kind: .ghost))
                    }

                    if let rawWritten = model.lastRawWritten {
                        Divider()
                            .overlay(Color.primary.opacity(0.10))

                        let rawPath = rawWritten.rawURL.path(percentEncoded: false)
                        Text(rawPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                            .contextMenu {
                                Button("Copy") { UIPasteboard.general.string = rawPath }
                            }

                        HStack(spacing: 10) {
                            ShareLink(item: rawWritten.rawURL) {
                                Label("Share JSONL", systemImage: "doc.plaintext")
                                    .labelStyle(.titleAndIcon)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NucleusButtonStyle(kind: .secondary))

                            ShareLink(item: rawWritten.metaURL) {
                                Label("Share Meta", systemImage: "doc.text")
                                    .labelStyle(.titleAndIcon)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NucleusButtonStyle(kind: .ghost))
                        }
                    }
                } else {
                    Text("Nothing exported yet.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    var telemetryCard: some View {
        NucleusCard("Telemetry", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 12) {
                if let revision = model.latestRevision {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(revision.date)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(compactTimezone(revision.day.timezone))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength: 0)
                        StatusPill(label: compactTimezone(revision.day.timezone), kind: .neutral, systemImage: "globe")
                    }

                    let keys: [MetricKey] = [
                        .steps,
                        .activeEnergyKcal,
                        .exerciseMinutes,
                        .standHours,
                        .restingHrAvg,
                        .hrvSdnnAvg,
                        .sleepAsleepMinutes,
                        .sleepInBedMinutes,
                    ]

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(keys) { key in
                            MetricTile(key: key, result: metricResult(key, revision: revision))
                        }
                    }
                } else {
                    Text("Run Sync Now to see metrics.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("Uploads run best-effort. If you need reliability, re-run sync or build a retry queue.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }

    var backendLabel: String {
        switch model.storageStatus?.backend {
        case .icloudDrive:
            "iCloud"
        case .localDocuments:
            "Local"
        case nil:
            "Unknown"
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
        model.objectStoreSettings.enabled ? "S3 on" : "S3 off"
    }

    var objectStoreIcon: String {
        model.objectStoreSettings.enabled ? "shippingbox.fill" : "shippingbox"
    }

    var objectStoreKind: StatusPill.Kind {
        if !model.objectStoreSettings.enabled { return .neutral }
        return model.resolvedObjectStoreConfig() != nil ? .ok : .warning
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
}

private struct MetricTile: View {
    let key: MetricKey
    let result: MetricResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))

                    Circle()
                        .stroke(tint.opacity(0.22), lineWidth: 1)

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
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
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
            "OK"
        case .no_data:
            "NO DATA"
        case .unauthorized:
            "NO AUTH"
        case .unsupported:
            "UNSUP"
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
        }
    }

    private var valueColor: Color {
        switch result.status {
        case .ok:
            NucleusPalette.accent
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
