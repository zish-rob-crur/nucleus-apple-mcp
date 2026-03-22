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
    @Published var isBootstrapping = false
    @Published var isSyncing = false
    @Published var isObjectStoreTesting = false
    @Published var isPresentingInitialSyncRangePicker = false
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
    @Published var syncProgress: SyncProgress?
    @Published var lastError: String?
    @Published var logs: [LogLine] = []
    @Published var activitySnapshot: NucleusActivitySnapshot

    private let collector = HealthCollector()
    private let storage = RevisionStorage()
    private let anchorStore = HealthAnchorStore()
    private let objectStoreUploader = S3ObjectStoreUploader()
    private lazy var identity = Self.loadOrCreateIdentity()
    private var objectStoreCredentials: ObjectStoreCredentials?
    private var healthObserverToken: NSObjectProtocol?
    private var pendingObserverEvents: [HealthObserverEvent] = []
    private var pendingObserverTypeKeys: Set<String> = []
    private var observerBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var hasCompletedInitialSync: Bool
    private var bootstrapTask: Task<Void, Never>?
    private var foregroundRefreshTask: Task<Void, Never>?
    private var hasCompletedBootstrap = false
    private var lastForegroundRefreshAt: Date?

    init() {
        let defaults = UserDefaults.standard
        // Health exports stay in private app storage in the shipping app path.
        self.preferICloud = false
        defaults.set(false, forKey: Self.preferICloudKey)
        let savedCatchUp = defaults.integer(forKey: Self.catchUpDaysKey)
        self.catchUpDays = (1...14).contains(savedCatchUp) ? savedCatchUp : 7
        self.hasCompletedInitialSync = defaults.bool(forKey: Self.initialSyncCompletedKey)
        self.objectStoreSettings = ObjectStoreSettingsStore.loadSettings()
        self.objectStoreHasCredentials = false
        self.objectStoreCredentials = nil
        self.activitySnapshot = NucleusActivityStore.load()
        registerHealthObserverNotifications()
        bootstrapIfNeeded()
    }

    var collectorId: String { identity.collectorId }
    var deviceId: String { identity.deviceId }
    var needsInitialSyncRangeSelection: Bool { !hasCompletedInitialSync }
    var manualSyncButtonTitle: String {
        if isBootstrapping { return "Loading…" }
        if isSyncing { return "Syncing…" }
        return needsInitialSyncRangeSelection ? "Start First Sync" : "Sync Now"
    }

    var orbState: NucleusOrb.State {
        if isSyncing { return .syncing }
        if lastError != nil { return .error }
        if authRequestStatus == .shouldRequest { return .needsPermission }
        return .idle
    }

    func bootstrapIfNeeded() {
        guard bootstrapTask == nil, !hasCompletedBootstrap else { return }

        isBootstrapping = true
        bootstrapTask = Task { [weak self] in
            await self?.runBootstrap()
        }
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
        publishActivitySnapshot()
    }

    func refreshAnchorDiagnostics() async {
        anchorDiagnostics = await anchorStore.diagnostics(expectedTypeKeys: HealthCollector.incrementalTypeKeys)
        if anchorDiagnostics.primedTypeCount > 0, !hasCompletedInitialSync {
            markInitialSyncCompleted()
        }
        publishActivitySnapshot()
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
        publishActivitySnapshot()
    }

    func refreshStorageStatus(preferICloud: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            await self.refreshStorageStatusNow(preferICloud: preferICloud)
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

    func beginManualSync() {
        guard !isSyncing else { return }

        if needsInitialSyncRangeSelection {
            isPresentingInitialSyncRangePicker = true
            return
        }

        syncNow(catchUpDays: catchUpDays)
    }

    func startInitialSync(option: InitialSyncRangeOption) {
        isPresentingInitialSyncRangePicker = false
        log(.info, "Initial sync window selected: \(option.title) (\(option.days)d).")
        syncNow(catchUpDays: option.days)
    }

    func openInitialSyncRangePicker() {
        guard !isSyncing, needsInitialSyncRangeSelection else { return }
        isPresentingInitialSyncRangePicker = true
    }

    func dismissInitialSyncRangePicker() {
        isPresentingInitialSyncRangePicker = false
    }

    func runHistoryBackfill(option: InitialSyncRangeOption) {
        guard !isSyncing else { return }
        log(.info, "History backfill requested: \(option.title) (\(option.days)d).")
        _ = startSync(catchUpDays: option.days, source: .backfill(option.days))
    }

    @discardableResult
    private func startSync(catchUpDays: Int, source: SyncSource) -> Bool {
        if isSyncing {
            if case .observer(let typeKeys) = source {
                pendingObserverTypeKeys.formUnion(typeKeys)
                PendingBackgroundSyncStore.save(typeKeys: pendingObserverTypeKeys.sorted())
                log(.info, "Queued observer sync while another sync is running.")
            }
            return false
        }

        guard let storageStatus else {
            lastError = "Storage is not configured."
            publishActivitySnapshot()
            if case .observer = source {
                completePendingObserverEvents()
            }
            return false
        }

        isSyncing = true
        lastError = nil
        let effectiveCatchUpDays = effectiveCatchUpDays(for: catchUpDays, source: source)
        let progressMode = syncProgressMode(for: source)
        setSyncProgress(SyncProgress(phase: .planning, mode: progressMode))
        publishActivitySnapshot()
        log(.info, source.startMessage(windowDays: effectiveCatchUpDays))

        Task {
            defer { finalizeSyncCycle() }

            let timeZone = TimeZone.current
            let objectStoreConfig = resolvedObjectStoreConfig()
            if let objectStoreConfig {
                log(.info, "Object store enabled → s3://\(objectStoreConfig.bucket)/\(objectStoreConfig.prefix.isEmpty ? "" : objectStoreConfig.prefix + "/")…")
            }

            do {
                let syncPlan: IncrementalSyncPlan
                switch source {
                case .backfill(let days):
                    syncPlan = await collector.prepareBackfillSyncPlan(
                        days: days,
                        timeZone: timeZone,
                        anchorStore: anchorStore
                    )
                case .manual, .observer, .scheduledRefresh:
                    syncPlan = await collector.prepareIncrementalSyncPlan(
                        catchUpDays: effectiveCatchUpDays,
                        timeZone: timeZone,
                        anchorStore: anchorStore
                    )
                }

                for (typeKey, message) in syncPlan.stats.typeErrors.sorted(by: { $0.key < $1.key }) {
                    log(.error, "Anchor sync skipped for \(typeKey): \(message)")
                }

                if !syncPlan.stats.primedTypeKeys.isEmpty {
                    log(.info, "Primed anchors for \(syncPlan.stats.primedTypeKeys.sorted().joined(separator: ", ")).")
                }

                if syncPlan.stats.bootstrapWindowUsed {
                    log(.info, "Using \(effectiveCatchUpDays)d bootstrap window.")
                }

                if syncPlan.stats.fallbackWindowUsed {
                    log(.info, "Using \(effectiveCatchUpDays)d fallback window for unresolved deletions.")
                }

                if syncPlan.affectedDates.isEmpty {
                    log(.info, "No HealthKit changes since the last sync.")
                    PendingBackgroundSyncStore.clear()
                    return
                }

                let commitId = RevisionId.generate(now: Date())
                var commitChanges: [HealthCommitDateChange] = []
                let totalDates = syncPlan.affectedDates.count

                for (index, ymd) in syncPlan.affectedDates.enumerated() {
                    setSyncProgress(SyncProgress(
                        phase: .collecting,
                        mode: progressMode,
                        completedDates: index,
                        totalDates: totalDates,
                        currentDateIndex: index + 1,
                        currentDate: ymd
                    ))

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
                        publishActivitySnapshot()
                    }

                    log(.success, "Wrote \(ymd) → \(written.dailyURL.lastPathComponent)")
                    let rawCount = raw.meta.typeCounts.values.reduce(0, +)
                    log(.success, "Wrote raw \(ymd) → \(rawWritten.manifestURL.lastPathComponent) (\(rawCount) samples)")

                    if let objectStoreConfig {
                        let uploadTargets = [written.dailyURL, written.monthURL, rawWritten.manifestURL] + rawWritten.sampleURLs
                        setSyncProgress(SyncProgress(
                            phase: .uploading,
                            mode: progressMode,
                            completedDates: index,
                            totalDates: totalDates,
                            currentDateIndex: index + 1,
                            currentDate: ymd,
                            uploadedFiles: 0,
                            totalUploadFiles: uploadTargets.count
                        ))

                        for (uploadIndex, target) in uploadTargets.enumerated() {
                            let result = try await objectStoreUploader.putFile(target, relativeTo: storageStatus.rootURL, config: objectStoreConfig)
                            log(.success, "Uploaded \(ymd) → s3://\(objectStoreConfig.bucket)/\(result.key)")
                            setSyncProgress(SyncProgress(
                                phase: .uploading,
                                mode: progressMode,
                                completedDates: index,
                                totalDates: totalDates,
                                currentDateIndex: index + 1,
                                currentDate: ymd,
                                uploadedFiles: uploadIndex + 1,
                                totalUploadFiles: uploadTargets.count
                            ))
                        }
                    }

                    setSyncProgress(SyncProgress(
                        phase: .collecting,
                        mode: progressMode,
                        completedDates: index + 1,
                        totalDates: totalDates,
                        currentDateIndex: index + 1,
                        currentDate: ymd
                    ))
                }

                setSyncProgress(SyncProgress(
                    phase: .finalizing,
                    mode: progressMode,
                    completedDates: totalDates,
                    totalDates: totalDates
                ))

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
                PendingBackgroundSyncStore.clear()
                await refreshAnchorDiagnostics()
                let primedCount = syncPlan.proposedState.types.values.filter(\.isPrimed).count
                markInitialSyncCompleted()
                log(.success, "Anchor state updated (\(primedCount) primed types).")
            } catch {
                lastError = error.localizedDescription
                publishActivitySnapshot()
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
        switch phase {
        case .active:
            bootstrapIfNeeded()
            guard hasCompletedBootstrap else { return }
            scheduleForegroundRefreshIfNeeded()
            Task { [weak self] in
                guard let self else { return }
                _ = await self.processPendingBackgroundSyncIfPossible()
            }
        case .background:
            scheduleBackgroundRefresh()
        default:
            break
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
        guard hasCompletedInitialSync else {
            log(.info, "Health observer fired for \(event.typeKey), waiting for the first manual sync to complete.")
            event.complete()
            return
        }

        guard event.errorMessage == nil else {
            log(.error, "Health observer error (\(event.typeKey)): \(event.errorMessage!)")
            event.complete()
            return
        }

        pendingObserverEvents.append(event)
        pendingObserverTypeKeys.insert(event.typeKey)
        PendingBackgroundSyncStore.save(typeKeys: pendingObserverTypeKeys.sorted())
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
        publishActivitySnapshot()
        clearSyncProgress()
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
        preferICloud = false
        UserDefaults.standard.set(false, forKey: Self.preferICloudKey)
        refreshStorageStatus(preferICloud: false)
    }

    func setCatchUpDays(_ value: Int) {
        let clamped = min(14, max(1, value))
        catchUpDays = clamped
        UserDefaults.standard.set(clamped, forKey: Self.catchUpDaysKey)
    }

    func saveObjectStoreSettings(_ settings: ObjectStoreSettings) {
        objectStoreSettings = settings
        ObjectStoreSettingsStore.saveSettings(settings)
        publishActivitySnapshot()
    }

    func saveObjectStoreCredentials(accessKeyId: String, secretAccessKey: String) {
        do {
            let credentials = ObjectStoreCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
            try ObjectStoreSettingsStore.saveCredentials(credentials)
            objectStoreCredentials = credentials
            objectStoreHasCredentials = true
        } catch {
            objectStoreCredentials = nil
            objectStoreHasCredentials = false
            lastError = error.localizedDescription
        }
        publishActivitySnapshot()
    }

    func clearObjectStoreCredentials() {
        ObjectStoreSettingsStore.clearCredentials()
        objectStoreCredentials = nil
        objectStoreHasCredentials = false
        publishActivitySnapshot()
    }

    func resolvedObjectStoreConfig(requireEnabled: Bool = true) -> S3ObjectStoreConfig? {
        if requireEnabled, !objectStoreSettings.enabled { return nil }
        guard let endpointURL = objectStoreSettings.endpointURL else { return nil }
        guard !objectStoreSettings.bucket.isEmpty else { return nil }
        guard let credentials = objectStoreCredentials else { return nil }

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

    private func runBootstrap() async {
        let preferICloud = preferICloud
        async let resolvedStorageTask = Self.resolveStorageStatus(preferICloud: preferICloud)
        async let credentialsTask = Self.loadCachedObjectStoreCredentials()

        await refreshAuthStatus()
        await refreshAnchorDiagnostics()

        let credentials = await credentialsTask
        objectStoreCredentials = credentials
        objectStoreHasCredentials = credentials != nil

        applyStorageResolution(await resolvedStorageTask)

        hasCompletedBootstrap = true
        lastForegroundRefreshAt = Date()
        isBootstrapping = false
        bootstrapTask = nil
        publishActivitySnapshot()
    }

    private func scheduleForegroundRefreshIfNeeded() {
        guard foregroundRefreshTask == nil else { return }

        if let lastForegroundRefreshAt,
           Date().timeIntervalSince(lastForegroundRefreshAt) < Self.foregroundRefreshInterval {
            return
        }

        foregroundRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAuthStatus()
            await self.refreshAnchorDiagnostics()
            await self.refreshStorageStatusNow(preferICloud: self.preferICloud)
            _ = await self.processPendingBackgroundSyncIfPossible()
            self.lastForegroundRefreshAt = Date()
            self.foregroundRefreshTask = nil
        }
    }

    func handleBackgroundRefreshTask() async {
        defer { scheduleBackgroundRefresh() }

        await waitForBootstrapIfNeeded()
        guard !Task.isCancelled else { return }

        await refreshAuthStatus()
        await refreshAnchorDiagnostics()
        await refreshStorageStatusNow(preferICloud: preferICloud)
        guard !Task.isCancelled else { return }

        if await processPendingBackgroundSyncIfPossible() {
            return
        }

        guard canRunBackgroundSync else { return }

        log(.info, "Running scheduled background refresh.")
        if startSync(catchUpDays: catchUpDays, source: .scheduledRefresh) {
            await waitForSyncToFinish()
        }
    }

    private func scheduleBackgroundRefresh() {
        do {
            try NucleusBackgroundRefresh.schedule()
        } catch {
            log(.error, "Unable to schedule background refresh: \(error.localizedDescription)")
        }
    }

    private func waitForBootstrapIfNeeded() async {
        bootstrapIfNeeded()
        while isBootstrapping {
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
        }
    }

    private func waitForSyncToFinish() async {
        while isSyncing {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
        }
    }

    @discardableResult
    private func processPendingBackgroundSyncIfPossible() async -> Bool {
        guard canRunBackgroundSync else { return false }
        guard let request = PendingBackgroundSyncStore.load() else { return false }

        let summary = request.typeKeys.isEmpty ? "queued changes" : request.typeKeys.joined(separator: ", ")
        log(.info, "Resuming queued background sync (\(summary)).")

        guard startSync(catchUpDays: catchUpDays, source: .observer(request.typeKeys)) else {
            return false
        }

        await waitForSyncToFinish()
        return true
    }

    private func refreshStorageStatusNow(preferICloud: Bool) async {
        let resolved = await Self.resolveStorageStatus(preferICloud: preferICloud)
        applyStorageResolution(resolved)
    }

    private func applyStorageResolution(_ resolution: StorageResolution) {
        switch resolution {
        case .success(let status):
            storageStatus = status
            if Self.isRecoverableStorageError(lastError) {
                lastError = nil
            }
        case .failure(let message):
            storageStatus = nil
            lastError = message
        }
        publishActivitySnapshot()
    }

    private static func resolveStorageStatus(preferICloud: Bool) async -> StorageResolution {
        await Task.detached(priority: .utility) {
            let storage = RevisionStorage()
            do {
                return .success(try storage.resolveStatus(preferICloud: preferICloud))
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    private static func loadCachedObjectStoreCredentials() async -> ObjectStoreCredentials? {
        await Task.detached(priority: .utility) {
            ObjectStoreSettingsStore.loadCredentials()
        }.value
    }

    private static func normalizedErrorMessage(_ message: String?) -> String? {
        message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isRecoverableStorageError(_ message: String?) -> Bool {
        guard let message else { return false }
        let normalized = normalizedErrorMessage(message) ?? ""
        return normalized == "storage is not configured."
            || normalized == "unable to resolve storage root."
            || normalized.contains("ubiquity")
            || normalized.contains("icloud")
    }

    private func log(_ level: LogLine.Level, _ message: String) {
        logs.insert(LogLine(level: level, message: message), at: 0)
        if logs.count > 80 {
            logs.removeLast(logs.count - 80)
        }
    }

    private func markInitialSyncCompleted() {
        guard !hasCompletedInitialSync else { return }
        hasCompletedInitialSync = true
        UserDefaults.standard.set(true, forKey: Self.initialSyncCompletedKey)
        publishActivitySnapshot()
    }

    private func publishActivitySnapshot() {
        let previous = activitySnapshot
        let phase = currentActivityPhase(previous: previous)
        let storageLabel = currentStorageLabel ?? previous.storageLabel
        let uploadLabel = currentUploadLabel
        let syncModeLabel = currentSyncModeLabel
        let revisionId = lastWritten?.revisionId ?? previous.revisionId
        let lastSyncAt = NucleusActivitySnapshot.iso8601Date(from: latestRevision?.generatedAt) ?? previous.lastSyncAt
        let errorMessage = phase == .error ? (lastError ?? previous.errorMessage) : nil

        let changed =
            phase != previous.phase ||
            storageLabel != previous.storageLabel ||
            uploadLabel != previous.uploadLabel ||
            syncModeLabel != previous.syncModeLabel ||
            revisionId != previous.revisionId ||
            lastSyncAt != previous.lastSyncAt ||
            errorMessage != previous.errorMessage

        let snapshot = NucleusActivitySnapshot(
            phase: phase,
            storageLabel: storageLabel,
            uploadLabel: uploadLabel,
            syncModeLabel: syncModeLabel,
            revisionId: revisionId,
            lastSyncAt: lastSyncAt,
            lastUpdatedAt: changed ? Date() : previous.lastUpdatedAt,
            errorMessage: errorMessage
        )

        activitySnapshot = snapshot
        NucleusActivityStore.save(snapshot)
    }

    private func setSyncProgress(_ progress: SyncProgress) {
        syncProgress = progress
        Task {
            await NucleusLiveActivityController.upsert(progress: progress)
        }
    }

    private func effectiveCatchUpDays(for requestedDays: Int, source: SyncSource) -> Int {
        switch source {
        case .manual, .backfill:
            return requestedDays
        case .observer, .scheduledRefresh:
            return min(requestedDays, Self.maxBackgroundCatchUpDays)
        }
    }

    private func syncProgressMode(for source: SyncSource) -> SyncProgress.Mode {
        switch source {
        case .manual:
            return .incremental
        case .backfill(let days):
            return .backfill(days)
        case .observer, .scheduledRefresh:
            return .background
        }
    }

    private func clearSyncProgress() {
        syncProgress = nil
        let snapshot = activitySnapshot
        let failed = lastError != nil
        Task {
            await NucleusLiveActivityController.end(snapshot: snapshot, failed: failed)
        }
    }

    private func currentActivityPhase(previous: NucleusActivitySnapshot) -> NucleusActivityPhase {
        if isSyncing { return .syncing }
        if let lastError,
           !(storageStatus != nil && Self.isRecoverableStorageError(lastError)) {
            return .error
        }
        if authRequestStatus == .shouldRequest { return .needsAuthorization }
        if !hasCompletedInitialSync && previous.lastSyncAt == nil { return .setup }
        return .ready
    }

    private var currentStorageLabel: String? {
        switch storageStatus?.backend {
        case .icloudDrive:
            "Private"
        case .localDocuments:
            "Private"
        case nil:
            nil
        }
    }

    private var currentUploadLabel: String {
        guard objectStoreSettings.enabled else { return "S3 Off" }
        return resolvedObjectStoreConfig() != nil ? "S3 On" : "S3 Setup"
    }

    private var currentSyncModeLabel: String {
        switch anchorDiagnostics.modeLabel {
        case "bootstrap":
            "First export"
        case "partial":
            "Backfill"
        default:
            "Incremental"
        }
    }

    private var canRunBackgroundSync: Bool {
        hasCompletedBootstrap &&
        hasCompletedInitialSync &&
        !isSyncing &&
        authRequestStatus == .unnecessary &&
        storageStatus != nil
    }

    private static let preferICloudKey = "nucleus.prefer_icloud_drive"
    private static let catchUpDaysKey = "nucleus.catch_up_days"
    private static let initialSyncCompletedKey = "nucleus.initial_sync_completed"
    private static let foregroundRefreshInterval: TimeInterval = 3
    private static let maxBackgroundCatchUpDays = 3
}

private enum StorageResolution: Sendable {
    case success(StorageStatus)
    case failure(String)
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

enum InitialSyncRangeOption: Int, CaseIterable, Identifiable {
    case oneMonth = 30
    case threeMonths = 90
    case sixMonths = 180
    case oneYear = 365

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .oneMonth:
            "Recent 1 month"
        case .threeMonths:
            "Recent 3 months"
        case .sixMonths:
            "Recent 6 months"
        case .oneYear:
            "Recent 1 year"
        }
    }

    var subtitle: String {
        switch self {
        case .oneMonth:
            "Recommended · faster first import"
        case .threeMonths:
            "More history with moderate sync time"
        case .sixMonths:
            "Good for broader trends and backfill"
        case .oneYear:
            "Largest initial import"
        }
    }
}

struct SyncProgress: Equatable {
    enum Phase: Equatable {
        case planning
        case collecting
        case uploading
        case finalizing
    }

    enum Mode: Equatable {
        case incremental
        case backfill(Int)
        case background
    }

    let phase: Phase
    var mode: Mode = .incremental
    var completedDates: Int = 0
    var totalDates: Int = 0
    var currentDateIndex: Int?
    var currentDate: String?
    var uploadedFiles: Int = 0
    var totalUploadFiles: Int = 0

    var contextLabel: String? {
        switch mode {
        case .incremental:
            return nil
        case .backfill(let days):
            return "History Backfill · \(days)d"
        case .background:
            return "Background Sync"
        }
    }

    var title: String {
        switch (mode, phase) {
        case (.backfill, .planning):
            "Preparing History Backfill"
        case (.backfill, .collecting):
            "Re-exporting Health History"
        case (.backfill, .uploading):
            "Uploading Backfill Files"
        case (.backfill, .finalizing):
            "Finalizing Backfill"
        case (.background, .planning):
            "Preparing Background Sync"
        case (.background, .collecting):
            "Refreshing Health Data"
        case (.background, .uploading):
            "Uploading Background Updates"
        case (.background, .finalizing):
            "Finalizing Background Sync"
        case (_, .planning):
            "Preparing Sync"
        case (_, .collecting):
            "Collecting Health Data"
        case (_, .uploading):
            "Uploading Files"
        case (_, .finalizing):
            "Finalizing Sync"
        }
    }

    var detail: String {
        switch (mode, phase) {
        case (.backfill(let days), .planning):
            return "Preparing the last \(days) days for re-export…"
        case (.backfill, .collecting):
            if let currentDateIndex, let currentDate, totalDates > 0 {
                return "Rewriting day \(currentDateIndex) of \(totalDates) · \(currentDate)"
            }
            return "Re-exporting the selected history window…"
        case (.backfill, .uploading):
            if let currentDate {
                return "Uploading backfill files \(uploadedFiles) / \(max(totalUploadFiles, 1)) · \(currentDate)"
            }
            return "Uploading refreshed history…"
        case (.backfill, .finalizing):
            return "Saving refreshed history and commit metadata…"
        case (.background, .planning):
            return "Building a background sync plan from recent HealthKit changes…"
        case (.background, .collecting):
            if let currentDateIndex, let currentDate, totalDates > 0 {
                return "Refreshing day \(currentDateIndex) of \(totalDates) · \(currentDate)"
            }
            return "Collecting HealthKit changes from background delivery…"
        case (.background, .uploading):
            if let currentDate {
                return "Uploading \(uploadedFiles) / \(max(totalUploadFiles, 1)) files · \(currentDate)"
            }
            return "Uploading background sync files…"
        case (.background, .finalizing):
            return "Saving background sync metadata…"
        case (_, .planning):
            return "Building the incremental sync plan…"
        case (_, .collecting):
            if let currentDateIndex, let currentDate, totalDates > 0 {
                return "Syncing day \(currentDateIndex) of \(totalDates) · \(currentDate)"
            }
            return "Collecting changed HealthKit dates…"
        case (_, .uploading):
            if let currentDate {
                return "Uploading \(uploadedFiles) / \(max(totalUploadFiles, 1)) files · \(currentDate)"
            }
            return "Uploading exported files…"
        case (_, .finalizing):
            return "Writing commit metadata and saving anchor state…"
        }
    }

    var phaseLabel: String {
        switch (mode, phase) {
        case (.backfill, .collecting):
            "backfilling"
        case (.background, .collecting):
            "background"
        case (_, .planning):
            "planning"
        case (_, .collecting):
            "collecting"
        case (_, .uploading):
            "uploading"
        case (_, .finalizing):
            "finalizing"
        }
    }

    var phaseIcon: String {
        switch (mode, phase) {
        case (.backfill, .planning):
            "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case (.background, .planning):
            "waveform.badge.magnifyingglass"
        case (_, .planning):
            "wand.and.stars"
        case (_, .collecting):
            "calendar"
        case (_, .uploading):
            "arrow.up.circle"
        case (_, .finalizing):
            "checkmark.seal"
        }
    }

    var supportingNote: String {
        switch mode {
        case .incremental:
            return "When Live Activities are allowed, this same run can appear on the Lock Screen and Dynamic Island."
        case .backfill(let days):
            return "This run is rewriting the last \(days) days. Larger backfills can take a while before the first upload finishes."
        case .background:
            return "This run started from HealthKit background delivery and is refreshing your export without opening the app."
        }
    }

    var dateProgressValue: Double? {
        guard totalDates > 0 else { return nil }
        return min(max(Double(completedDates) / Double(totalDates), 0), 1)
    }

    var dateProgressLabel: String? {
        guard totalDates > 0 else { return nil }
        return "\(completedDates) / \(totalDates) days"
    }

    var uploadProgressValue: Double? {
        guard totalUploadFiles > 0 else { return nil }
        return min(max(Double(uploadedFiles) / Double(totalUploadFiles), 0), 1)
    }

    var uploadProgressLabel: String? {
        guard totalUploadFiles > 0 else { return nil }
        return "\(uploadedFiles) / \(totalUploadFiles) files"
    }
}

private enum SyncSource {
    case manual
    case backfill(Int)
    case observer([String])
    case scheduledRefresh

    func startMessage(windowDays: Int) -> String {
        switch self {
        case .manual:
            return "Sync started (window: \(windowDays)d)…"
        case .backfill(let days):
            return "History backfill started (\(days)d)…"
        case .observer(let typeKeys):
            let summary = typeKeys.isEmpty ? "observer" : typeKeys.joined(separator: ", ")
            return "Background sync started (\(summary), window: \(windowDays)d)…"
        case .scheduledRefresh:
            return "Scheduled refresh started (window: \(windowDays)d)…"
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

struct ObjectStoreCredentials: Equatable, Sendable {
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
