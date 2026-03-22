import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum NucleusActivityPhase: String, Codable, Sendable {
    case ready
    case syncing
    case needsAuthorization
    case setup
    case error
}

struct NucleusActivitySnapshot: Codable, Equatable, Sendable {
    let phase: NucleusActivityPhase
    let storageLabel: String
    let uploadLabel: String
    let syncModeLabel: String
    let revisionId: String?
    let lastSyncAt: Date?
    let lastUpdatedAt: Date
    let errorMessage: String?

    var title: String {
        switch phase {
        case .ready:
            "Ready"
        case .syncing:
            "Syncing"
        case .needsAuthorization:
            "Health Access"
        case .setup:
            "First Sync"
        case .error:
            "Needs Attention"
        }
    }

    var detail: String {
        switch phase {
        case .ready:
            if let lastSyncAt {
                return "Last synced \(Self.relativeString(for: lastSyncAt))."
            }
            return "Exports are available on your device."
        case .syncing:
            return "Updating your recent export now."
        case .needsAuthorization:
            return "Grant Health access to keep your export current."
        case .setup:
            return "Run the first sync to establish your history."
        case .error:
            return errorMessage ?? "The latest sync needs review in the app."
        }
    }

    var metaLine: String {
        [storageLabel, uploadLabel, syncModeLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var shortRevision: String? {
        revisionId.map { String($0.suffix(8)).uppercased() }
    }

    static let placeholder = NucleusActivitySnapshot(
        phase: .ready,
        storageLabel: "Local",
        uploadLabel: "S3 Off",
        syncModeLabel: "Incremental",
        revisionId: "20260314123000-AB12CD34",
        lastSyncAt: Date().addingTimeInterval(-48 * 60),
        lastUpdatedAt: Date(),
        errorMessage: nil
    )

    static let empty = NucleusActivitySnapshot(
        phase: .setup,
        storageLabel: "Local",
        uploadLabel: "S3 Off",
        syncModeLabel: "First export",
        revisionId: nil,
        lastSyncAt: nil,
        lastUpdatedAt: .distantPast,
        errorMessage: nil
    )

    static func iso8601Date(from string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

enum NucleusSharedState {
    static let appGroupID = "group.com.zhiwenwang.nucleus"
    static let widgetKind = "NucleusSyncStatusWidget"
    static let snapshotKey = "nucleus.activity.snapshot"
}

enum NucleusActivityStore {
    static func load() -> NucleusActivitySnapshot {
        guard
            let defaults = UserDefaults(suiteName: NucleusSharedState.appGroupID),
            let data = defaults.data(forKey: NucleusSharedState.snapshotKey),
            let snapshot = try? JSONDecoder().decode(NucleusActivitySnapshot.self, from: data)
        else {
            return .empty
        }

        return snapshot
    }

    static func save(_ snapshot: NucleusActivitySnapshot) {
        let current = load()
        guard current != snapshot else { return }
        guard let defaults = UserDefaults(suiteName: NucleusSharedState.appGroupID) else { return }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: NucleusSharedState.snapshotKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: NucleusSharedState.widgetKind)
        #endif
    }
}
