import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                networkCard
                fallbackCard
                backfillCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, NucleusStyle.floatingTabBarClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(NucleusBackground())
        .navigationTitle("Sync Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SyncSettingsView()
            .environmentObject(AppModel())
    }
}

private extension SyncSettingsView {
    var header: some View {
        NucleusCard("Sync", systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tune incremental fallback behavior and manually re-run a longer history backfill whenever you want older data re-exported.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    StatusPill(label: model.anchorDiagnostics.modeLabel, kind: model.anchorDiagnostics.unprimedTypeKeys.isEmpty ? .ok : .warning, systemImage: "bolt.badge.clock")
                    StatusPill(label: model.syncProgress?.phaseLabel ?? "idle", kind: model.isSyncing ? .neutral : .ok, systemImage: model.syncProgress?.phaseIcon ?? "checkmark.circle")
                }
            }
        }
    }

    var fallbackCard: some View {
        NucleusCard("Fallback Window", systemImage: "calendar.badge.exclamationmark") {
            VStack(alignment: .leading, spacing: 12) {
                NucleusInset {
                    Stepper(value: Binding(
                        get: { model.catchUpDays },
                        set: { model.setCatchUpDays($0) }
                    ), in: 1...14) {
                        HStack {
                            Text("Incremental fallback window")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Text("\(model.catchUpDays)d")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                Text("This window is used after the first sync when HealthKit reports deletions without enough local context.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.needsInitialSyncRangeSelection {
                    Button {
                        model.openInitialSyncRangePicker()
                    } label: {
                        Label("Choose First Sync Range", systemImage: "clock.badge")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .secondary))
                    .disabled(model.isSyncing || model.isSyncPausedForNetwork)
                }
            }
        }
    }

    var networkCard: some View {
        NucleusCard("Network", systemImage: "wifi") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Network sync policy")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(model.networkSyncDetail)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    StatusPill(label: model.networkSyncStatus.label, kind: networkStatusKind, systemImage: networkStatusIcon)
                }

                NucleusInset {
                    Toggle(isOn: Binding(
                        get: { model.allowCellularSync },
                        set: { model.setAllowCellularSync($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow mobile data")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(networkPolicyNote)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(NucleusPalette.accent)
                }
            }
        }
    }

    var backfillCard: some View {
        NucleusCard("History Backfill", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Re-run a longer sync window to import older history again. This is safe to repeat and will rewrite affected daily snapshots.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(InitialSyncRangeOption.allCases) { option in
                    Button {
                        model.runHistoryBackfill(option: option)
                    } label: {
                        NucleusInset {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(option.subtitle)
                                        .font(.system(.footnote, design: .rounded))
                                        .foregroundStyle(Color.secondary)
                                }

                                Spacer(minLength: 0)

                                Text("\(option.days)d")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(NucleusPalette.accentForeground(colorScheme))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSyncing || model.isSyncPausedForNetwork)
                }
            }
        }
    }

    var networkStatusKind: StatusPill.Kind {
        switch model.networkSyncStatus {
        case .wifi, .other:
            .ok
        case .unknown:
            .warning
        case .unavailable, .cellular:
            .neutral
        }
    }

    var networkStatusIcon: String {
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

    var networkPolicyNote: String {
        if model.allowCellularSync {
            return "Sync can run on Wi-Fi or mobile data. Low Data Mode still blocks uploads."
        }
        return "Mobile data is held as a pending sync and resumes automatically on Wi-Fi or another non-cellular connection."
    }
}
