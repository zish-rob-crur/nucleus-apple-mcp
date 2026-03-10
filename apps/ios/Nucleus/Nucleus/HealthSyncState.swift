import Foundation

extension Notification.Name {
    static let nucleusHealthObserverDidFire = Notification.Name("nucleus.health.observer.did_fire")
}

final class HealthObserverEvent: @unchecked Sendable {
    let typeKey: String
    let errorMessage: String?
    private let completionHandler: () -> Void
    private let lock = NSLock()
    private var didComplete = false

    init(typeKey: String, errorMessage: String? = nil, completionHandler: @escaping () -> Void) {
        self.typeKey = typeKey
        self.errorMessage = errorMessage
        self.completionHandler = completionHandler
    }

    func complete() {
        let completion: () -> Void
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        completion = completionHandler
        lock.unlock()
        completion()
    }
}

struct TrackedSampleState: Codable, Equatable {
    let dates: [String]
}

struct AnchoredTypeState: Codable, Equatable {
    var isPrimed: Bool = false
    var anchorData: Data?
    var trackedSamples: [String: TrackedSampleState] = [:]
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case isPrimed = "is_primed"
        case anchorData = "anchor_data"
        case trackedSamples = "tracked_samples"
        case updatedAt = "updated_at"
    }
}

struct HealthAnchorState: Codable, Equatable {
    let schemaVersion: String
    var updatedAt: String
    var types: [String: AnchoredTypeState]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case types
    }

    static func empty(now: Date = Date()) -> Self {
        HealthAnchorState(
            schemaVersion: "health.anchor_state.v1",
            updatedAt: ISO8601.utcString(now),
            types: [:]
        )
    }
}

struct AnchoredSyncStats: Equatable {
    var primedTypeKeys: [String] = []
    var addedSamples: Int = 0
    var deletedSamples: Int = 0
    var unknownDeletedSamples: Int = 0
    var bootstrapWindowUsed = false
    var fallbackWindowUsed = false
    var typeErrors: [String: String] = [:]
}

struct IncrementalSyncPlan {
    let affectedDates: [String]
    let changedTypeKeysByDate: [String: [String]]
    let proposedState: HealthAnchorState
    let stats: AnchoredSyncStats
}

struct HealthAnchorDiagnostics: Equatable {
    let primedTypeCount: Int
    let totalTypeCount: Int
    let trackedSampleCount: Int
    let unprimedTypeKeys: [String]

    var modeLabel: String {
        if primedTypeCount == 0 { return "bootstrap" }
        if unprimedTypeKeys.isEmpty { return "incremental" }
        return "partial"
    }

    var typeCoverageLabel: String {
        "\(primedTypeCount)/\(totalTypeCount)"
    }

    static let empty = HealthAnchorDiagnostics(
        primedTypeCount: 0,
        totalTypeCount: 0,
        trackedSampleCount: 0,
        unprimedTypeKeys: []
    )
}

actor HealthAnchorStore {
    private let fileManager = FileManager.default
    private let fileName = "health-anchor-state.json"

    func loadState() -> HealthAnchorState {
        do {
            let url = try stateFileURL(createParent: false)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                return HealthAnchorState.empty()
            }

            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(HealthAnchorState.self, from: data)
            return decoded
        } catch {
            do {
                let url = try stateFileURL(createParent: true)
                if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                    let backup = url.deletingLastPathComponent()
                        .appendingPathComponent("health-anchor-state.corrupt-\(UUID().uuidString).json", isDirectory: false)
                    try? fileManager.moveItem(at: url, to: backup)
                }
            } catch {
            }
            return HealthAnchorState.empty()
        }
    }

    func saveState(_ state: HealthAnchorState) throws {
        let url = try stateFileURL(createParent: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(state).write(to: url, options: [.atomic])
    }

    func diagnostics(expectedTypeKeys: [String]) -> HealthAnchorDiagnostics {
        let state = loadState()
        let primedTypeCount = expectedTypeKeys.filter { state.types[$0]?.isPrimed == true }.count
        let trackedSampleCount = state.types.values.reduce(into: 0) { partial, typeState in
            partial += typeState.trackedSamples.count
        }
        let unprimedTypeKeys = expectedTypeKeys.filter { state.types[$0]?.isPrimed != true }

        return HealthAnchorDiagnostics(
            primedTypeCount: primedTypeCount,
            totalTypeCount: expectedTypeKeys.count,
            trackedSampleCount: trackedSampleCount,
            unprimedTypeKeys: unprimedTypeKeys
        )
    }

    private func stateFileURL(createParent: Bool) throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RevisionStorageError.cannotResolveRoot
        }

        let directory = base.appendingPathComponent("Nucleus", isDirectory: true)
        if createParent {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
