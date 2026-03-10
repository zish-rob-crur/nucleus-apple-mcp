import Foundation
import SwiftUI
import HealthKit
import Security
import UIKit

enum AppModelError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Keychain error: \(status)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isAuthorizing = false
    @Published var isSyncing = false
    @Published var isObjectStoreTesting = false
    @Published var authRequestStatus: HKAuthorizationRequestStatus = .unknown
    @Published var latestRevision: DailyRevision?
    @Published var lastWritten: WrittenRevision?
    @Published var lastRawWritten: WrittenRawSamples?
    @Published var preferICloud: Bool
    @Published var catchUpDays: Int
    @Published var objectStoreSettings: ObjectStoreSettings
    @Published var objectStoreHasCredentials: Bool
    @Published var lastObjectStoreTest: ObjectStoreTestResult?
    @Published var storageStatus: StorageStatus?
    @Published var anchorDiagnostics: HealthAnchorDiagnostics = .empty
    @Published var backgroundDeliveryStatus: BackgroundDeliveryStatus = .idle
    @Published var lastError: String?
    @Published var logs: [LogLine] = []

    private let collector = HealthCollector()
    private let storage = RevisionStorage()
    private let anchorStore = HealthAnchorStore()
    private let objectStoreUploader = S3ObjectStoreUploader()
    private let identity: CollectorIdentity
    private var healthObserverToken: NSObjectProtocol?
    private var pendingObserverEvents: [HealthObserverEvent] = []
    private var pendingObserverTypeKeys: Set<String> = []
    private var observerBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init() {
        let defaults = UserDefaults.standard
        self.preferICloud = defaults.object(forKey: Self.preferICloudKey) as? Bool ?? true
        let savedCatchUp = defaults.integer(forKey: Self.catchUpDaysKey)
        self.catchUpDays = (1...14).contains(savedCatchUp) ? savedCatchUp : 7

        self.identity = Self.loadOrCreateIdentity()
        self.objectStoreSettings = ObjectStoreSettingsStore.loadSettings()
        self.objectStoreHasCredentials = ObjectStoreSettingsStore.loadCredentials() != nil
        registerHealthObserverNotifications()
        collector.ensureObserverQueriesRunning()
        Task {
            await refreshAuthStatus()
            await refreshAnchorDiagnostics()
        }
        refreshStorageStatus(preferICloud: preferICloud)
    }

    var collectorId: String { identity.collectorId }
    var deviceId: String { identity.deviceId }

    var orbState: NucleusOrb.State {
        if isSyncing { return .syncing }
        if lastError != nil { return .error }
        if authRequestStatus == .shouldRequest { return .needsPermission }
        return .idle
    }

    func refreshAuthStatus() async {
        authRequestStatus = await collector.authorizationRequestStatus()
        switch authRequestStatus {
        case .unnecessary:
            await configureHealthObserversIfPossible()
        case .shouldRequest:
            backgroundDeliveryStatus = .needsAuthorization
        case .unknown:
            backgroundDeliveryStatus = .idle
        @unknown default:
            backgroundDeliveryStatus = .idle
        }
    }

    func refreshAnchorDiagnostics() async {
        anchorDiagnostics = await anchorStore.diagnostics(expectedTypeKeys: HealthCollector.incrementalTypeKeys)
    }

    func configureHealthObserversIfPossible() async {
        let result = await collector.ensureBackgroundDeliveryEnabled()

        if !result.errors.isEmpty {
            backgroundDeliveryStatus = .error(result.errors)
            for (typeKey, message) in result.errors.sorted(by: { $0.key < $1.key }) {
                log(.error, "Background delivery failed for \(typeKey): \(message)")
            }
            return
        }

        let enabledKeys = result.enabledDeliveryKeys
        backgroundDeliveryStatus = .ready(enabledKeys)
        if !enabledKeys.isEmpty {
            log(.success, "Background delivery enabled for \(enabledKeys.joined(separator: ", ")).")
        }
    }

    func refreshStorageStatus(preferICloud: Bool = true) {
        do {
            storageStatus = try storage.resolveStatus(preferICloud: preferICloud)
        } catch {
            storageStatus = nil
            lastError = error.localizedDescription
        }
    }

    func requestHealthAuthorization() {
        guard !isAuthorizing else { return }

        isAuthorizing = true
        lastError = nil
        log(.info, "Requesting HealthKit authorization…")

        Task {
            do {
                try await collector.requestAuthorization()
                log(.success, "HealthKit authorization flow completed.")
            } catch {
                lastError = error.localizedDescription
                log(.error, "Authorization failed: \(error.localizedDescription)")
            }
            isAuthorizing = false
            await refreshAuthStatus()
        }
    }

    func syncNow(catchUpDays: Int = 7) {
        _ = startSync(catchUpDays: catchUpDays, source: .manual)
    }

    @discardableResult
    private func startSync(catchUpDays: Int, source: SyncSource) -> Bool {
        if isSyncing {
            if case .observer(let typeKeys) = source {
                pendingObserverTypeKeys.formUnion(typeKeys)
                log(.info, "Queued observer sync while another sync is running.")
            }
            return false
        }

        guard let storageStatus else {
            lastError = "Storage is not configured."
            if case .observer = source {
                completePendingObserverEvents()
            }
            return false
        }

        isSyncing = true
        lastError = nil
        log(.info, source.startMessage(windowDays: catchUpDays))

        Task {
            defer { finalizeSyncCycle() }

            let timeZone = TimeZone.current
            let objectStoreConfig = resolvedObjectStoreConfig()
            if let objectStoreConfig {
                log(.info, "Object store enabled → s3://\(objectStoreConfig.bucket)/\(objectStoreConfig.prefix.isEmpty ? "" : objectStoreConfig.prefix + "/")…")
            }

            do {
                let syncPlan = await collector.prepareIncrementalSyncPlan(
                    catchUpDays: catchUpDays,
                    timeZone: timeZone,
                    anchorStore: anchorStore
                )

                for (typeKey, message) in syncPlan.stats.typeErrors.sorted(by: { $0.key < $1.key }) {
                    log(.error, "Anchor sync skipped for \(typeKey): \(message)")
                }

                if !syncPlan.stats.primedTypeKeys.isEmpty {
                    log(.info, "Primed anchors for \(syncPlan.stats.primedTypeKeys.sorted().joined(separator: ", ")).")
                }

                if syncPlan.stats.bootstrapWindowUsed {
                    log(.info, "Using \(catchUpDays)d bootstrap window.")
                }

                if syncPlan.stats.fallbackWindowUsed {
                    log(.info, "Using \(catchUpDays)d fallback window for unresolved deletions.")
                }

                if syncPlan.affectedDates.isEmpty {
                    log(.info, "No HealthKit changes since the last sync.")
                    return
                }

                let commitId = RevisionId.generate(now: Date())
                var commitChanges: [HealthCommitDateChange] = []

                for ymd in syncPlan.affectedDates {
                    guard let date = DateFormatting.date(from: ymd, in: timeZone) else {
                        throw RevisionStorageError.invalidDate(ymd)
                    }
                    let rawManifestRelpath = RevisionStorage.rawManifestRelpath(for: ymd)
                    log(.info, "Collecting \(ymd)…")

                    let (revision, generatedAt) = try await collector.makeDailyRevision(
                        for: date,
                        timeZone: timeZone,
                        collector: identity,
                        commitId: commitId,
                        rawManifestRelpath: rawManifestRelpath
                    )
                    let written = try storage.writeDailyRevision(revision, storage: storageStatus)

                    let raw = await collector.exportRawSamples(for: date, timeZone: timeZone, collector: identity, generatedAt: generatedAt)
                    let rawWritten = try storage.writeRawSamples(raw, revisionId: commitId, storage: storageStatus)

                    commitChanges.append(
                        HealthCommitDateChange(
                            date: ymd,
                            dailyRelpath: RevisionStorage.dailyDateRelpath(for: ymd),
                            monthRelpath: RevisionStorage.dailyMonthRelpath(for: ymd),
                            rawManifestRelpath: rawManifestRelpath,
                            rawTypeKeys: syncPlan.changedTypeKeysByDate[ymd] ?? raw.meta.typeStatus.keys.sorted()
                        )
                    )

                    if commitChanges.count == 1 {
                        latestRevision = revision
                        lastWritten = written
                        lastRawWritten = rawWritten
                    }

                    log(.success, "Wrote \(ymd) → \(written.dailyURL.lastPathComponent)")
                    let rawCount = raw.meta.typeCounts.values.reduce(0, +)
                    log(.success, "Wrote raw \(ymd) → \(rawWritten.manifestURL.lastPathComponent) (\(rawCount) samples)")

                    if let objectStoreConfig {
                        let uploadTargets = [written.dailyURL, written.monthURL, rawWritten.manifestURL] + rawWritten.sampleURLs
                        for target in uploadTargets {
                            let result = try await objectStoreUploader.putFile(target, relativeTo: storageStatus.rootURL, config: objectStoreConfig)
                            log(.success, "Uploaded \(ymd) → s3://\(objectStoreConfig.bucket)/\(result.key)")
                        }
                    }
                }

                let commit = HealthSyncCommit(
                    schemaVersion: "health.commit.v1",
                    commitId: commitId,
                    generatedAt: ISO8601.utcString(Date()),
                    collector: CollectorPayload(collectorId: identity.collectorId, deviceId: identity.deviceId),
                    dates: commitChanges.sorted { $0.date < $1.date }
                )
                let commitURL = try storage.writeCommit(commit, storage: storageStatus)
                log(.success, "Wrote commit → \(commitURL.lastPathComponent)")

                if let objectStoreConfig {
                    let result = try await objectStoreUploader.putFile(commitURL, relativeTo: storageStatus.rootURL, config: objectStoreConfig)
                    log(.success, "Uploaded commit → s3://\(objectStoreConfig.bucket)/\(result.key)")
                }

                try await anchorStore.saveState(syncPlan.proposedState)
                await refreshAnchorDiagnostics()
                let primedCount = syncPlan.proposedState.types.values.filter(\.isPrimed).count
                log(.success, "Anchor state updated (\(primedCount) primed types).")
            } catch {
                lastError = error.localizedDescription
                log(.error, "Sync failed: \(error.localizedDescription)")
            }

            log(.info, "Sync finished.")
        }

        return true
    }

    func clearLogs() {
        logs.removeAll()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        Task {
            await refreshAuthStatus()
            await refreshAnchorDiagnostics()
        }
    }

    private func registerHealthObserverNotifications() {
        healthObserverToken = NotificationCenter.default.addObserver(
            forName: .nucleusHealthObserverDidFire,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let event = notification.object as? HealthObserverEvent else { return }
            Task { @MainActor [weak self] in
                self?.handleHealthObserverEvent(event)
            }
        }
    }

    private func handleHealthObserverEvent(_ event: HealthObserverEvent) {
        guard event.errorMessage == nil else {
            log(.error, "Health observer error (\(event.typeKey)): \(event.errorMessage!)")
            event.complete()
            return
        }

        pendingObserverEvents.append(event)
        pendingObserverTypeKeys.insert(event.typeKey)
        beginObserverBackgroundTaskIfNeeded()
        log(.info, "Health observer fired for \(event.typeKey).")

        if isSyncing {
            log(.info, "Observer-triggered sync queued.")
            return
        }

        let typeKeys = consumePendingObserverTypeKeys()
        if !startSync(catchUpDays: catchUpDays, source: .observer(typeKeys)) {
            completePendingObserverEvents()
        }
    }

    private func finalizeSyncCycle() {
        isSyncing = false
        Task { await refreshAnchorDiagnostics() }

        let followUpTypeKeys = consumePendingObserverTypeKeys()
        guard !followUpTypeKeys.isEmpty else {
            completePendingObserverEvents()
            return
        }

        log(.info, "Running follow-up observer sync.")
        if !startSync(catchUpDays: catchUpDays, source: .observer(followUpTypeKeys)) {
            completePendingObserverEvents()
        }
    }

    private func consumePendingObserverTypeKeys() -> [String] {
        let typeKeys = pendingObserverTypeKeys.sorted()
        pendingObserverTypeKeys.removeAll()
        return typeKeys
    }

    private func completePendingObserverEvents() {
        let events = pendingObserverEvents
        pendingObserverEvents.removeAll()
        for event in events {
            event.complete()
        }
        endObserverBackgroundTaskIfNeeded()
    }

    private func beginObserverBackgroundTaskIfNeeded() {
        guard observerBackgroundTaskID == .invalid else { return }
        observerBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "nucleus.health.observer.sync") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.log(.error, "Background HealthKit delivery expired before sync completed.")
                self.completePendingObserverEvents()
            }
        }
    }

    private func endObserverBackgroundTaskIfNeeded() {
        guard observerBackgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(observerBackgroundTaskID)
        observerBackgroundTaskID = .invalid
    }

    func setPreferICloud(_ value: Bool) {
        preferICloud = value
        UserDefaults.standard.set(value, forKey: Self.preferICloudKey)
        refreshStorageStatus(preferICloud: value)
    }

    func setCatchUpDays(_ value: Int) {
        let clamped = min(14, max(1, value))
        catchUpDays = clamped
        UserDefaults.standard.set(clamped, forKey: Self.catchUpDaysKey)
    }

    func saveObjectStoreSettings(_ settings: ObjectStoreSettings) {
        objectStoreSettings = settings
        ObjectStoreSettingsStore.saveSettings(settings)
    }

    func saveObjectStoreCredentials(accessKeyId: String, secretAccessKey: String) {
        do {
            try ObjectStoreSettingsStore.saveCredentials(.init(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey))
            objectStoreHasCredentials = true
        } catch {
            objectStoreHasCredentials = false
            lastError = error.localizedDescription
        }
    }

    func clearObjectStoreCredentials() {
        ObjectStoreSettingsStore.clearCredentials()
        objectStoreHasCredentials = false
    }

    func resolvedObjectStoreConfig(requireEnabled: Bool = true) -> S3ObjectStoreConfig? {
        if requireEnabled, !objectStoreSettings.enabled { return nil }
        guard let endpointURL = objectStoreSettings.endpointURL else { return nil }
        guard !objectStoreSettings.bucket.isEmpty else { return nil }
        guard let credentials = ObjectStoreSettingsStore.loadCredentials() else { return nil }

        return S3ObjectStoreConfig(
            endpoint: endpointURL,
            region: objectStoreSettings.region,
            bucket: objectStoreSettings.bucket,
            prefix: objectStoreSettings.prefix,
            usePathStyle: objectStoreSettings.usePathStyle,
            credentials: credentials
        )
    }

    func testObjectStore() {
        guard !isObjectStoreTesting else { return }

        guard let config = resolvedObjectStoreConfig(requireEnabled: false) else {
            let message = "Object store config is incomplete. Fill endpoint/bucket and save credentials first."
            lastObjectStoreTest = ObjectStoreTestResult(timestamp: Date(), success: false, message: message)
            log(.error, "Object store test failed: incomplete config.")
            return
        }

        isObjectStoreTesting = true
        lastObjectStoreTest = nil

        log(.info, "Testing object store upload…")

        let now = Date()
        let testId = RevisionId.generate(now: now, randomHexLength: 12)
        let baseKey = "_nucleus/probes/\(testId).json"
        let trimmedPrefix = config.prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = trimmedPrefix.isEmpty ? baseKey : "\(trimmedPrefix)/\(baseKey)"

        let payload: [String: String] = [
            "record": "probe",
            "schema_version": "nucleus.object_store.probe.v1",
            "generated_at": ISO8601.utcString(now),
            "id": testId,
        ]

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nucleus-object-store-probe-\(testId).json", isDirectory: false)

        Task {
            defer { isObjectStoreTesting = false }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
                try data.write(to: tempURL, options: [.atomic])

                let result = try await objectStoreUploader.putFile(tempURL, bucket: config.bucket, key: key, config: config)
                let location = "s3://\(config.bucket)/\(result.key)"
                let etag = result.etag ?? "unknown"
                let message = "OK: uploaded probe → \(location) (etag: \(etag))"

                lastObjectStoreTest = ObjectStoreTestResult(timestamp: Date(), success: true, message: message)
                log(.success, "Object store test ok → \(location)")
            } catch {
                let message = "FAIL: \(error.localizedDescription)"
                lastObjectStoreTest = ObjectStoreTestResult(timestamp: Date(), success: false, message: message)
                log(.error, "Object store test failed: \(error.localizedDescription)")
            }
        }
    }

    private static func loadOrCreateIdentity() -> CollectorIdentity {
        let collectorId = (try? Keychain.loadOrCreate(account: "collector_id")) ?? UUID().uuidString
        let deviceId = (try? Keychain.loadOrCreate(account: "device_id")) ?? UUID().uuidString
        return CollectorIdentity(collectorId: collectorId, deviceId: deviceId)
    }

    private func log(_ level: LogLine.Level, _ message: String) {
        logs.insert(LogLine(level: level, message: message), at: 0)
        if logs.count > 80 {
            logs.removeLast(logs.count - 80)
        }
    }

    private static let preferICloudKey = "nucleus.prefer_icloud_drive"
    private static let catchUpDaysKey = "nucleus.catch_up_days"
}

struct LogLine: Identifiable, Equatable {
    enum Level: String {
        case info
        case success
        case error
    }

    let id = UUID()
    let timestamp = Date()
    let level: Level
    let message: String
}

enum BackgroundDeliveryStatus: Equatable {
    case idle
    case needsAuthorization
    case ready([String])
    case error([String: String])

    var label: String {
        switch self {
        case .idle:
            "idle"
        case .needsAuthorization:
            "auth"
        case .ready:
            "ready"
        case .error:
            "error"
        }
    }
}

private enum SyncSource {
    case manual
    case observer([String])

    func startMessage(windowDays: Int) -> String {
        switch self {
        case .manual:
            return "Sync started (window: \(windowDays)d)…"
        case .observer(let typeKeys):
            let summary = typeKeys.isEmpty ? "observer" : typeKeys.joined(separator: ", ")
            return "Background sync started (\(summary), window: \(windowDays)d)…"
        }
    }
}

struct ObjectStoreTestResult: Equatable {
    let timestamp: Date
    let success: Bool
    let message: String
}

enum Keychain {
    static func loadOrCreate(account: String) throws -> String {
        if let existing = load(account: account) {
            return existing
        }
        let created = UUID().uuidString
        try save(created, account: account)
        return created
    }

    static func load(account: String) -> String? {
        var query: [String: Any] = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)

        var query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let attributes = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw AppModelError.keychain(updateStatus) }
            return
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AppModelError.keychain(addStatus) }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        let service = Bundle.main.bundleIdentifier ?? "com.nucleus.nucleus"
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}

struct ObjectStoreSettings: Codable, Equatable {
    var enabled: Bool = false
    var endpoint: String = ""
    var region: String = "auto"
    var bucket: String = ""
    var prefix: String = ""
    var usePathStyle: Bool = true

    var endpointURL: URL? {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(string: "https://\(raw)")
    }
}

struct ObjectStoreCredentials: Equatable {
    let accessKeyId: String
    let secretAccessKey: String
}

enum ObjectStoreSettingsStore {
    private static let settingsKey = "nucleus.object_store.settings.v1"
    private static let accessKeyAccount = "object_store_access_key_id"
    private static let secretKeyAccount = "object_store_secret_access_key"

    static func loadSettings() -> ObjectStoreSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return ObjectStoreSettings() }
        do {
            return try JSONDecoder().decode(ObjectStoreSettings.self, from: data)
        } catch {
            return ObjectStoreSettings()
        }
    }

    static func saveSettings(_ settings: ObjectStoreSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: settingsKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: settingsKey)
        }
    }

    static func loadCredentials() -> ObjectStoreCredentials? {
        guard let accessKeyId = Keychain.load(account: accessKeyAccount),
              let secretAccessKey = Keychain.load(account: secretKeyAccount) else {
            return nil
        }
        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else { return nil }
        return ObjectStoreCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
    }

    static func saveCredentials(_ credentials: ObjectStoreCredentials) throws {
        try Keychain.save(credentials.accessKeyId, account: accessKeyAccount)
        try Keychain.save(credentials.secretAccessKey, account: secretKeyAccount)
    }

    static func clearCredentials() {
        _ = deleteKeychainItem(account: accessKeyAccount)
        _ = deleteKeychainItem(account: secretKeyAccount)
    }

    private static func deleteKeychainItem(account: String) -> OSStatus {
        let service = Bundle.main.bundleIdentifier ?? "com.nucleus.nucleus"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
    }
}

struct S3ObjectStoreConfig: Equatable {
    let endpoint: URL
    let region: String
    let bucket: String
    let prefix: String
    let usePathStyle: Bool
    let credentials: ObjectStoreCredentials
}
