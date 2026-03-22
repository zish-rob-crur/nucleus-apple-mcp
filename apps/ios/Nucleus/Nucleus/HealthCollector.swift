import Foundation
import HealthKit

enum HealthCollectorError: Error, LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "Health data is unavailable on this device."
        }
    }
}

final class HealthCollector: @unchecked Sendable {
    private let store = HKHealthStore()
    private static let anchoredBatchSize = 2000
    private var observerQueries: [String: HKObserverQuery] = [:]
    private var backgroundDeliveryEnabledKeys: Set<String> = []

    private enum RawKey: String, CaseIterable {
        case stepCount = "step_count"
        case activeEnergyBurned = "active_energy_burned"
        case heartRate = "heart_rate"
        case restingHeartRate = "resting_heart_rate"
        case hrvSDNN = "hrv_sdnn"
        case vo2Max = "vo2_max"
        case oxygenSaturation = "oxygen_saturation"
        case respiratoryRate = "respiratory_rate"
        case wristTemperature = "apple_sleeping_wrist_temperature"
        case bodyMass = "body_mass"
        case bodyFatPercentage = "body_fat_percentage"
        case bloodPressure = "blood_pressure"
        case bloodGlucose = "blood_glucose"
        case bodyTemperature = "body_temperature"
        case basalBodyTemperature = "basal_body_temperature"
        case sleepAnalysis = "sleep_analysis"
        case workout = "workout"
    }

    static var incrementalTypeKeys: [String] {
        RawKey.allCases.map(\.rawValue)
    }

    struct ObserverConfigurationResult {
        var startedQueryKeys: [String] = []
        var enabledDeliveryKeys: [String] = []
        var errors: [String: String] = [:]
    }

    private static let percentUnit = HKUnit.percent()
    private static let respiratoryRateUnit = HKUnit.count().unitDivided(by: .minute())
    private static let vo2MaxUnit = HKUnit(from: "mL/(kg*min)")
    private static let bloodGlucoseUnit = HKUnit(from: "mg/dL")
    private static let pressureUnit = HKUnit.millimeterOfMercury()
    private static let temperatureUnit = HKUnit.degreeCelsius()

    private static func percentValue(_ raw: Double) -> Double {
        raw * 100.0
    }

    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unknown }

        let readTypes = Self.authorizationReadTypes
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthCollectorError.healthDataUnavailable }
        try await store.requestAuthorization(toShare: [], read: Self.authorizationReadTypes)
    }

    func ensureObserverQueriesRunning() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        for descriptor in Self.anchoredDescriptors {
            guard observerQueries[descriptor.key.rawValue] == nil else { continue }

            let query = HKObserverQuery(sampleType: descriptor.type, predicate: nil) { _, completionHandler, error in
                let event = HealthObserverEvent(
                    typeKey: descriptor.key.rawValue,
                    errorMessage: error?.localizedDescription,
                    completionHandler: completionHandler
                )
                NotificationCenter.default.post(name: .nucleusHealthObserverDidFire, object: event)
            }

            observerQueries[descriptor.key.rawValue] = query
            store.execute(query)
        }
    }

    func ensureBackgroundDeliveryEnabled() async -> ObserverConfigurationResult {
        var result = ObserverConfigurationResult()
        guard HKHealthStore.isHealthDataAvailable() else { return result }

        ensureObserverQueriesRunning()
        result.startedQueryKeys = observerQueries.keys.sorted()

        for descriptor in Self.anchoredDescriptors {
            guard !backgroundDeliveryEnabledKeys.contains(descriptor.key.rawValue) else { continue }

            do {
                try await enableBackgroundDelivery(for: descriptor.type, frequency: .immediate)
                backgroundDeliveryEnabledKeys.insert(descriptor.key.rawValue)
                result.enabledDeliveryKeys.append(descriptor.key.rawValue)
            } catch {
                result.errors[descriptor.key.rawValue] = error.localizedDescription
            }
        }

        result.startedQueryKeys.sort()
        result.enabledDeliveryKeys.sort()
        return result
    }

    func makeDailyRevision(
        for date: Date,
        timeZone: TimeZone,
        collector: CollectorIdentity,
        commitId: String,
        rawManifestRelpath: String
    ) async throws -> (revision: DailyRevision, generatedAt: Date) {
        guard HKHealthStore.isHealthDataAvailable() else {
            let generatedAt = Date()
            return (
                revision: Self.unsupportedRevision(
                    for: date,
                    timeZone: timeZone,
                    collector: collector,
                    generatedAt: generatedAt,
                    commitId: commitId,
                    rawManifestRelpath: rawManifestRelpath
                ),
                generatedAt: generatedAt
            )
        }

        let generatedAt = Date()
        let dayWindow = Self.dayWindow(for: date, timeZone: timeZone)

        let steps: MetricResult = if let type = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            await queryCumulativeSum(
                type: type,
                unit: .count(),
                day: dayWindow
            )
        } else {
            MetricResult(value: nil, status: .unsupported, unit: MetricKey.steps.unitString)
        }

        let resting: MetricResult = if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            await queryDiscreteAverage(
                type: type,
                unit: HKUnit.count().unitDivided(by: .minute()),
                unitString: MetricKey.restingHrAvg.unitString,
                day: dayWindow
            )
        } else {
            MetricResult(value: nil, status: .unsupported, unit: MetricKey.restingHrAvg.unitString)
        }

        let hrv: MetricResult = if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            await queryDiscreteAverage(
                type: type,
                unit: HKUnit.secondUnit(with: .milli),
                unitString: MetricKey.hrvSdnnAvg.unitString,
                day: dayWindow
            )
        } else {
            MetricResult(value: nil, status: .unsupported, unit: MetricKey.hrvSdnnAvg.unitString)
        }

        let vo2Max = await metricForLatest(
            typeIdentifier: .vo2Max,
            unit: Self.vo2MaxUnit,
            key: .vo2Max,
            day: dayWindow
        )

        let oxygenSaturation = await metricForAverage(
            typeIdentifier: .oxygenSaturation,
            unit: Self.percentUnit,
            key: .oxygenSaturationPct,
            day: dayWindow,
            transform: Self.percentValue
        )

        let respiratoryRate = await metricForAverage(
            typeIdentifier: .respiratoryRate,
            unit: Self.respiratoryRateUnit,
            key: .respiratoryRateAvg,
            day: dayWindow
        )

        let wristTemperature = await metricForAverage(
            typeIdentifier: .appleSleepingWristTemperature,
            unit: Self.temperatureUnit,
            key: .wristTemperatureCelsius,
            day: dayWindow
        )

        let bodyMass = await metricForLatest(
            typeIdentifier: .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            key: .bodyMassKg,
            day: dayWindow
        )

        let bodyFat = await metricForLatest(
            typeIdentifier: .bodyFatPercentage,
            unit: Self.percentUnit,
            key: .bodyFatPercentage,
            day: dayWindow,
            transform: Self.percentValue
        )

        let bloodGlucose = await metricForLatest(
            typeIdentifier: .bloodGlucose,
            unit: Self.bloodGlucoseUnit,
            key: .bloodGlucoseMgDl,
            day: dayWindow
        )

        let bodyTemperature = await metricForLatest(
            typeIdentifier: .bodyTemperature,
            unit: Self.temperatureUnit,
            key: .bodyTemperatureCelsius,
            day: dayWindow
        )

        let basalBodyTemperature = await metricForLatest(
            typeIdentifier: .basalBodyTemperature,
            unit: Self.temperatureUnit,
            key: .basalBodyTemperatureCelsius,
            day: dayWindow
        )

        let bloodPressure = await queryLatestBloodPressure(day: dayWindow)

        let sleep: SleepResults = if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            await querySleepMinutes(type: type, day: dayWindow)
        } else {
            SleepResults(
                asleep: MetricResult(value: nil, status: .unsupported, unit: MetricKey.sleepAsleepMinutes.unitString),
                inBed: MetricResult(value: nil, status: .unsupported, unit: MetricKey.sleepInBedMinutes.unitString)
            )
        }

        let activity = await queryActivitySummary(day: dayWindow)

        let metricResults: [MetricKey: MetricResult] = [
            .steps: steps,
            .activeEnergyKcal: activity.activeEnergy,
            .exerciseMinutes: activity.exerciseMinutes,
            .standHours: activity.standHours,
            .restingHrAvg: resting,
            .hrvSdnnAvg: hrv,
            .vo2Max: vo2Max,
            .oxygenSaturationPct: oxygenSaturation,
            .respiratoryRateAvg: respiratoryRate,
            .wristTemperatureCelsius: wristTemperature,
            .bodyMassKg: bodyMass,
            .bodyFatPercentage: bodyFat,
            .bloodPressureSystolicMmhg: bloodPressure.systolic,
            .bloodPressureDiastolicMmhg: bloodPressure.diastolic,
            .bloodGlucoseMgDl: bloodGlucose,
            .bodyTemperatureCelsius: bodyTemperature,
            .basalBodyTemperatureCelsius: basalBodyTemperature,
            .sleepAsleepMinutes: sleep.asleep,
            .sleepInBedMinutes: sleep.inBed,
        ]

        let ymd = DateFormatting.ymdString(from: date, in: timeZone)
        let dayPayload = DayPayload(
            timezone: timeZone.identifier,
            start: ISO8601.zonedString(dayWindow.start, timeZone: timeZone),
            end: ISO8601.zonedString(dayWindow.end, timeZone: timeZone)
        )

        var metrics: [String: Double?] = [:]
        var metricStatus: [String: MetricStatus] = [:]
        var metricUnits: [String: String] = [:]

        for key in MetricKey.allCases {
            let result = metricResults[key] ?? MetricResult(value: nil, status: .no_data, unit: key.unitString)
            metrics[key.rawValue] = (result.status == .ok) ? result.value : nil
            metricStatus[key.rawValue] = result.status
            metricUnits[key.rawValue] = result.unit
        }

        let payload = DailyRevision(
            schemaVersion: "health.daily.v1",
            commitId: commitId,
            date: ymd,
            day: dayPayload,
            generatedAt: ISO8601.utcString(generatedAt),
            collector: CollectorPayload(collectorId: collector.collectorId, deviceId: collector.deviceId),
            metrics: metrics,
            metricStatus: metricStatus,
            metricUnits: metricUnits,
            rawManifestRelpath: rawManifestRelpath
        )

        return (payload, generatedAt)
    }

    func exportRawSamples(
        for date: Date,
        timeZone: TimeZone,
        collector: CollectorIdentity,
        generatedAt: Date
    ) async -> RawSamplesExport {
        let dayWindow = Self.dayWindow(for: date, timeZone: timeZone)
        let ymd = DateFormatting.ymdString(from: date, in: timeZone)
        let dayPayload = DayPayload(
            timezone: timeZone.identifier,
            start: ISO8601.zonedString(dayWindow.start, timeZone: timeZone),
            end: ISO8601.zonedString(dayWindow.end, timeZone: timeZone)
        )

        let collectorPayload = CollectorPayload(collectorId: collector.collectorId, deviceId: collector.deviceId)

        guard HKHealthStore.isHealthDataAvailable() else {
            let typeStatus = RawKey.allCases.reduce(into: [String: MetricStatus]()) { result, key in
                result[key.rawValue] = .unsupported
            }
            let typeCounts = RawKey.allCases.reduce(into: [String: Int]()) { result, key in
                result[key.rawValue] = 0
            }
            return RawSamplesExport(
                meta: RawSamplesMeta(
                    date: ymd,
                    day: dayPayload,
                    generatedAt: ISO8601.utcString(generatedAt),
                    collector: collectorPayload,
                    typeStatus: typeStatus,
                    typeCounts: typeCounts
                ),
                samples: []
            )
        }

        var typeStatus: [String: MetricStatus] = [:]
        var typeCounts: [String: Int] = [:]
        var sampleEntries: [(start: Date, record: RawSampleRecord)] = []

        func capture(
            key: RawKey,
            status: MetricStatus,
            entries: [(start: Date, record: RawSampleRecord)]
        ) {
            typeStatus[key.rawValue] = status
            typeCounts[key.rawValue] = (status == .ok) ? entries.count : 0
            sampleEntries.append(contentsOf: entries)
        }

        let stepCount = await exportQuantitySamples(
            key: .stepCount,
            typeIdentifier: .stepCount,
            unit: .count(),
            unitString: "count",
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .stepCount, status: stepCount.status, entries: stepCount.entries)

        let activeEnergyBurned = await exportQuantitySamples(
            key: .activeEnergyBurned,
            typeIdentifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            unitString: "kcal",
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .activeEnergyBurned, status: activeEnergyBurned.status, entries: activeEnergyBurned.entries)

        let heartRate = await exportQuantitySamples(
            key: .heartRate,
            typeIdentifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            unitString: "bpm",
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .heartRate, status: heartRate.status, entries: heartRate.entries)

        let restingHeartRate = await exportQuantitySamples(
            key: .restingHeartRate,
            typeIdentifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            unitString: "bpm",
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .restingHeartRate, status: restingHeartRate.status, entries: restingHeartRate.entries)

        let hrvSDNN = await exportQuantitySamples(
            key: .hrvSDNN,
            typeIdentifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            unitString: "ms",
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .hrvSDNN, status: hrvSDNN.status, entries: hrvSDNN.entries)

        let vo2Max = await exportQuantitySamples(
            key: .vo2Max,
            typeIdentifier: .vo2Max,
            unit: Self.vo2MaxUnit,
            unitString: MetricKey.vo2Max.unitString,
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .vo2Max, status: vo2Max.status, entries: vo2Max.entries)

        let oxygenSaturation = await exportQuantitySamples(
            key: .oxygenSaturation,
            typeIdentifier: .oxygenSaturation,
            unit: Self.percentUnit,
            unitString: MetricKey.oxygenSaturationPct.unitString,
            day: dayWindow,
            timeZone: timeZone,
            transform: Self.percentValue
        )
        capture(key: .oxygenSaturation, status: oxygenSaturation.status, entries: oxygenSaturation.entries)

        let respiratoryRate = await exportQuantitySamples(
            key: .respiratoryRate,
            typeIdentifier: .respiratoryRate,
            unit: Self.respiratoryRateUnit,
            unitString: MetricKey.respiratoryRateAvg.unitString,
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .respiratoryRate, status: respiratoryRate.status, entries: respiratoryRate.entries)

        let wristTemperature = await exportQuantitySamples(
            key: .wristTemperature,
            typeIdentifier: .appleSleepingWristTemperature,
            unit: Self.temperatureUnit,
            unitString: MetricKey.wristTemperatureCelsius.unitString,
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .wristTemperature, status: wristTemperature.status, entries: wristTemperature.entries)

        let bodyMass = await exportQuantitySamples(
            key: .bodyMass,
            typeIdentifier: .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            unitString: MetricKey.bodyMassKg.unitString,
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .bodyMass, status: bodyMass.status, entries: bodyMass.entries)

        let bodyFat = await exportQuantitySamples(
            key: .bodyFatPercentage,
            typeIdentifier: .bodyFatPercentage,
            unit: Self.percentUnit,
            unitString: MetricKey.bodyFatPercentage.unitString,
            day: dayWindow,
            timeZone: timeZone,
            transform: Self.percentValue
        )
        capture(key: .bodyFatPercentage, status: bodyFat.status, entries: bodyFat.entries)

        let bloodPressure = await exportBloodPressureSamples(day: dayWindow, timeZone: timeZone)
        capture(key: .bloodPressure, status: bloodPressure.status, entries: bloodPressure.entries)

        let bloodGlucose = await exportQuantitySamples(
            key: .bloodGlucose,
            typeIdentifier: .bloodGlucose,
            unit: Self.bloodGlucoseUnit,
            unitString: MetricKey.bloodGlucoseMgDl.unitString,
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .bloodGlucose, status: bloodGlucose.status, entries: bloodGlucose.entries)

        let bodyTemperature = await exportQuantitySamples(
            key: .bodyTemperature,
            typeIdentifier: .bodyTemperature,
            unit: Self.temperatureUnit,
            unitString: MetricKey.bodyTemperatureCelsius.unitString,
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .bodyTemperature, status: bodyTemperature.status, entries: bodyTemperature.entries)

        let basalBodyTemperature = await exportQuantitySamples(
            key: .basalBodyTemperature,
            typeIdentifier: .basalBodyTemperature,
            unit: Self.temperatureUnit,
            unitString: MetricKey.basalBodyTemperatureCelsius.unitString,
            day: dayWindow,
            timeZone: timeZone
        )
        capture(key: .basalBodyTemperature, status: basalBodyTemperature.status, entries: basalBodyTemperature.entries)

        let sleep = await exportSleepSamples(day: dayWindow, timeZone: timeZone)
        capture(key: .sleepAnalysis, status: sleep.status, entries: sleep.entries)

        let workouts = await exportWorkoutSamples(day: dayWindow, timeZone: timeZone)
        capture(key: .workout, status: workouts.status, entries: workouts.entries)

        for key in RawKey.allCases {
            typeStatus[key.rawValue] = typeStatus[key.rawValue] ?? .unsupported
            typeCounts[key.rawValue] = typeCounts[key.rawValue] ?? 0
        }

        sampleEntries.sort { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.record.key != rhs.record.key { return lhs.record.key < rhs.record.key }
            return lhs.record.uuid < rhs.record.uuid
        }

        let meta = RawSamplesMeta(
            date: ymd,
            day: dayPayload,
            generatedAt: ISO8601.utcString(generatedAt),
            collector: collectorPayload,
            typeStatus: typeStatus,
            typeCounts: typeCounts
        )

        return RawSamplesExport(meta: meta, samples: sampleEntries.map(\.record))
    }

    func prepareIncrementalSyncPlan(
        catchUpDays: Int,
        timeZone: TimeZone,
        anchorStore: HealthAnchorStore,
        now: Date = Date()
    ) async -> IncrementalSyncPlan {
        var state = await anchorStore.loadState()
        state.updatedAt = ISO8601.utcString(now)

        let fallbackDates = DateFormatting.recentYMDStrings(endingAt: now, days: catchUpDays, timeZone: timeZone)
        var affectedDates: Set<String> = []
        var changedTypeKeysByDate: [String: Set<String>] = [:]
        var stats = AnchoredSyncStats()
        var usedBootstrapWindow = false

        guard HKHealthStore.isHealthDataAvailable() else {
            for date in fallbackDates {
                affectedDates.insert(date)
                changedTypeKeysByDate[date, default: []].formUnion(Set(Self.incrementalTypeKeys))
            }
            stats.bootstrapWindowUsed = true
            return IncrementalSyncPlan(
                affectedDates: affectedDates.sorted(by: >),
                changedTypeKeysByDate: changedTypeKeysByDate.mapValues { $0.sorted() },
                proposedState: state,
                stats: stats
            )
        }

        var fallbackTypeKeys: Set<String> = []

        for descriptor in Self.anchoredDescriptors {
            var typeState = state.types[descriptor.key.rawValue] ?? AnchoredTypeState()
            do {
                let outcome = try await collectAnchoredChanges(
                    type: descriptor.type,
                    state: typeState,
                    timeZone: timeZone
                )

                let wasPrimed = typeState.isPrimed
                typeState.isPrimed = true
                typeState.anchorData = outcome.anchorData
                typeState.trackedSamples = outcome.trackedSamples
                typeState.updatedAt = ISO8601.utcString(now)
                state.types[descriptor.key.rawValue] = typeState

                if wasPrimed {
                    stats.addedSamples += outcome.addedSamples
                    stats.deletedSamples += outcome.deletedSamples
                    stats.unknownDeletedSamples += outcome.unknownDeletedSamples

                    if outcome.unknownDeletedSamples > 0 {
                        fallbackTypeKeys.insert(descriptor.key.rawValue)
                    }

                    for date in outcome.affectedDates {
                        affectedDates.insert(date)
                        changedTypeKeysByDate[date, default: []].insert(descriptor.key.rawValue)
                    }
                } else {
                    stats.primedTypeKeys.append(descriptor.key.rawValue)
                    usedBootstrapWindow = true
                }
            } catch {
                stats.typeErrors[descriptor.key.rawValue] = error.localizedDescription
                state.types[descriptor.key.rawValue] = typeState
            }
        }

        if usedBootstrapWindow || (affectedDates.isEmpty && state.types.values.allSatisfy { !$0.isPrimed }) {
            stats.bootstrapWindowUsed = true
            let bootstrapTypeKeys = Set(stats.primedTypeKeys.isEmpty ? Self.incrementalTypeKeys : stats.primedTypeKeys)
            for date in fallbackDates {
                affectedDates.insert(date)
                changedTypeKeysByDate[date, default: []].formUnion(bootstrapTypeKeys)
            }
        }

        if !fallbackTypeKeys.isEmpty {
            stats.fallbackWindowUsed = true
            for date in fallbackDates {
                affectedDates.insert(date)
                changedTypeKeysByDate[date, default: []].formUnion(fallbackTypeKeys)
            }
        }

        return IncrementalSyncPlan(
            affectedDates: affectedDates.sorted(by: >),
            changedTypeKeysByDate: changedTypeKeysByDate.mapValues { $0.sorted() },
            proposedState: state,
            stats: stats
        )
    }

    func prepareBackfillSyncPlan(
        days: Int,
        timeZone: TimeZone,
        anchorStore: HealthAnchorStore,
        now: Date = Date()
    ) async -> IncrementalSyncPlan {
        var state = await anchorStore.loadState()
        state.updatedAt = ISO8601.utcString(now)

        let affectedDates = DateFormatting.recentYMDStrings(
            endingAt: now,
            days: days,
            timeZone: timeZone
        )

        let changedTypeKeysByDate = Dictionary(
            uniqueKeysWithValues: affectedDates.map { ($0, Self.incrementalTypeKeys) }
        )

        return IncrementalSyncPlan(
            affectedDates: affectedDates,
            changedTypeKeysByDate: changedTypeKeysByDate,
            proposedState: state,
            stats: AnchoredSyncStats()
        )
    }

    private static var authorizationReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(activeEnergy) }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(resting) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let vo2Max = HKObjectType.quantityType(forIdentifier: .vo2Max) { types.insert(vo2Max) }
        if let oxygen = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) { types.insert(oxygen) }
        if let respiratory = HKObjectType.quantityType(forIdentifier: .respiratoryRate) { types.insert(respiratory) }
        if let wristTemp = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) { types.insert(wristTemp) }
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(bodyFat) }
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose) { types.insert(glucose) }
        if let bodyTemp = HKObjectType.quantityType(forIdentifier: .bodyTemperature) { types.insert(bodyTemp) }
        if let basalTemp = HKObjectType.quantityType(forIdentifier: .basalBodyTemperature) { types.insert(basalTemp) }
        if let systolic = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) { types.insert(systolic) }
        if let diastolic = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) { types.insert(diastolic) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.activitySummaryType())
        types.insert(HKObjectType.workoutType())
        return types
    }

    private struct AnchoredDescriptor {
        let key: RawKey
        let type: HKSampleType
    }

    private static var anchoredDescriptors: [AnchoredDescriptor] {
        var descriptors: [AnchoredDescriptor] = []
        if let type = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            descriptors.append(AnchoredDescriptor(key: .stepCount, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            descriptors.append(AnchoredDescriptor(key: .activeEnergyBurned, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            descriptors.append(AnchoredDescriptor(key: .heartRate, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            descriptors.append(AnchoredDescriptor(key: .restingHeartRate, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            descriptors.append(AnchoredDescriptor(key: .hrvSDNN, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            descriptors.append(AnchoredDescriptor(key: .vo2Max, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            descriptors.append(AnchoredDescriptor(key: .oxygenSaturation, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            descriptors.append(AnchoredDescriptor(key: .respiratoryRate, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            descriptors.append(AnchoredDescriptor(key: .wristTemperature, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            descriptors.append(AnchoredDescriptor(key: .bodyMass, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            descriptors.append(AnchoredDescriptor(key: .bodyFatPercentage, type: type))
        }
        if let type = HKObjectType.correlationType(forIdentifier: .bloodPressure) {
            descriptors.append(AnchoredDescriptor(key: .bloodPressure, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            descriptors.append(AnchoredDescriptor(key: .bloodGlucose, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) {
            descriptors.append(AnchoredDescriptor(key: .bodyTemperature, type: type))
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .basalBodyTemperature) {
            descriptors.append(AnchoredDescriptor(key: .basalBodyTemperature, type: type))
        }
        if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            descriptors.append(AnchoredDescriptor(key: .sleepAnalysis, type: type))
        }
        descriptors.append(AnchoredDescriptor(key: .workout, type: HKObjectType.workoutType()))
        return descriptors
    }

    private static func dayWindow(for date: Date, timeZone: TimeZone) -> DayWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return DayWindow(timeZone: timeZone, start: start, end: end)
    }

    private struct ActivityResults {
        let activeEnergy: MetricResult
        let exerciseMinutes: MetricResult
        let standHours: MetricResult
    }

    private struct BloodPressureResults {
        let systolic: MetricResult
        let diastolic: MetricResult
    }

    private func metricForAverage(
        typeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        key: MetricKey,
        day: DayWindow,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> MetricResult {
        guard let type = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return MetricResult(value: nil, status: .unsupported, unit: key.unitString)
        }
        return await queryDiscreteAverage(
            type: type,
            unit: unit,
            unitString: key.unitString,
            day: day,
            transform: transform
        )
    }

    private func metricForLatest(
        typeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        key: MetricKey,
        day: DayWindow,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> MetricResult {
        guard let type = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return MetricResult(value: nil, status: .unsupported, unit: key.unitString)
        }
        return await queryLatestQuantity(
            type: type,
            unit: unit,
            unitString: key.unitString,
            day: day,
            transform: transform
        )
    }

    private func queryActivitySummary(day: DayWindow) async -> ActivityResults {
        let timeZone = day.timeZone

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day.start)
        components.calendar = calendar
        components.timeZone = timeZone
        let predicate = HKQuery.predicateForActivitySummary(with: components)

        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error = error, let status = Self.mapToMetricStatus(error) {
                    continuation.resume(returning: ActivityResults(
                        activeEnergy: MetricResult(value: nil, status: status, unit: MetricKey.activeEnergyKcal.unitString),
                        exerciseMinutes: MetricResult(value: nil, status: status, unit: MetricKey.exerciseMinutes.unitString),
                        standHours: MetricResult(value: nil, status: status, unit: MetricKey.standHours.unitString)
                    ))
                    return
                }

                guard let summary = summaries?.first else {
                    continuation.resume(returning: ActivityResults(
                        activeEnergy: MetricResult(value: nil, status: .no_data, unit: MetricKey.activeEnergyKcal.unitString),
                        exerciseMinutes: MetricResult(value: nil, status: .no_data, unit: MetricKey.exerciseMinutes.unitString),
                        standHours: MetricResult(value: nil, status: .no_data, unit: MetricKey.standHours.unitString)
                    ))
                    return
                }

                let energy = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                let exercise = summary.appleExerciseTime.doubleValue(for: .minute())
                let stand = summary.appleStandHours.doubleValue(for: .count())

                continuation.resume(returning: ActivityResults(
                    activeEnergy: MetricResult(value: energy, status: .ok, unit: MetricKey.activeEnergyKcal.unitString),
                    exerciseMinutes: MetricResult(value: exercise, status: .ok, unit: MetricKey.exerciseMinutes.unitString),
                    standHours: MetricResult(value: stand, status: .ok, unit: MetricKey.standHours.unitString)
                ))
            }
            store.execute(query)
        }
    }

    private func exportQuantitySamples(
        key: RawKey,
        typeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        unitString: String,
        day: DayWindow,
        timeZone: TimeZone,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> (status: MetricStatus, entries: [(start: Date, record: RawSampleRecord)]) {
        guard let type = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return (status: .unsupported, entries: [])
        }

        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])
        do {
            let samples: [HKQuantitySample] = try await sampleQuery(
                type: type,
                predicate: predicate,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
                ]
            )

            guard !samples.isEmpty else {
                return (status: .no_data, entries: [])
            }

            let entries = samples.map { sample -> (start: Date, record: RawSampleRecord) in
                let source = sample.sourceRevision.source
                let device = sample.device
                let wasUserEntered = sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool

                return (
                    start: sample.startDate,
                    record: RawSampleRecord(
                        kind: .quantity,
                        key: key.rawValue,
                        hkIdentifier: typeIdentifier.rawValue,
                        uuid: sample.uuid.uuidString,
                        start: ISO8601.zonedString(sample.startDate, timeZone: timeZone),
                        end: ISO8601.zonedString(sample.endDate, timeZone: timeZone),
                        value: transform(sample.quantity.doubleValue(for: unit)),
                        unit: unitString,
                        categoryValue: nil,
                        categoryLabel: nil,
                        workoutActivityType: nil,
                        durationSec: nil,
                        totalEnergyKcal: nil,
                        totalDistanceM: nil,
                        components: nil,
                        componentUnits: nil,
                        sourceBundleId: source.bundleIdentifier,
                        sourceName: source.name,
                        deviceModel: device?.model,
                        deviceManufacturer: device?.manufacturer,
                        wasUserEntered: wasUserEntered
                    )
                )
            }

            return (status: .ok, entries: entries)
        } catch {
            return (status: Self.mapToMetricStatus(error) ?? .unauthorized, entries: [])
        }
    }

    private func exportBloodPressureSamples(
        day: DayWindow,
        timeZone: TimeZone
    ) async -> (status: MetricStatus, entries: [(start: Date, record: RawSampleRecord)]) {
        guard let type = HKObjectType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return (status: .unsupported, entries: [])
        }

        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])
        do {
            let samples: [HKCorrelation] = try await sampleQuery(
                type: type,
                predicate: predicate,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
                ]
            )

            guard !samples.isEmpty else {
                return (status: .no_data, entries: [])
            }

            let entries = samples.compactMap { sample -> (start: Date, record: RawSampleRecord)? in
                guard let systolicSample = sample.objects(for: systolicType).first as? HKQuantitySample,
                      let diastolicSample = sample.objects(for: diastolicType).first as? HKQuantitySample else {
                    return nil
                }

                let source = sample.sourceRevision.source
                let device = sample.device
                let wasUserEntered = sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool

                return (
                    start: sample.startDate,
                    record: RawSampleRecord(
                        kind: .correlation,
                        key: RawKey.bloodPressure.rawValue,
                        hkIdentifier: HKCorrelationTypeIdentifier.bloodPressure.rawValue,
                        uuid: sample.uuid.uuidString,
                        start: ISO8601.zonedString(sample.startDate, timeZone: timeZone),
                        end: ISO8601.zonedString(sample.endDate, timeZone: timeZone),
                        value: nil,
                        unit: nil,
                        categoryValue: nil,
                        categoryLabel: nil,
                        workoutActivityType: nil,
                        durationSec: nil,
                        totalEnergyKcal: nil,
                        totalDistanceM: nil,
                        components: [
                            "systolic_mmhg": systolicSample.quantity.doubleValue(for: Self.pressureUnit),
                            "diastolic_mmhg": diastolicSample.quantity.doubleValue(for: Self.pressureUnit),
                        ],
                        componentUnits: [
                            "systolic_mmhg": MetricKey.bloodPressureSystolicMmhg.unitString,
                            "diastolic_mmhg": MetricKey.bloodPressureDiastolicMmhg.unitString,
                        ],
                        sourceBundleId: source.bundleIdentifier,
                        sourceName: source.name,
                        deviceModel: device?.model,
                        deviceManufacturer: device?.manufacturer,
                        wasUserEntered: wasUserEntered
                    )
                )
            }

            return (status: entries.isEmpty ? .no_data : .ok, entries: entries)
        } catch {
            return (status: Self.mapToMetricStatus(error) ?? .unauthorized, entries: [])
        }
    }

    private func exportSleepSamples(
        day: DayWindow,
        timeZone: TimeZone
    ) async -> (status: MetricStatus, entries: [(start: Date, record: RawSampleRecord)]) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return (status: .unsupported, entries: [])
        }

        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])
        do {
            let samples: [HKCategorySample] = try await sampleQuery(
                type: type,
                predicate: predicate,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
                ]
            )

            guard !samples.isEmpty else {
                return (status: .no_data, entries: [])
            }

            let entries = samples.map { sample -> (start: Date, record: RawSampleRecord) in
                let source = sample.sourceRevision.source
                let device = sample.device
                let wasUserEntered = sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool

                return (
                    start: sample.startDate,
                    record: RawSampleRecord(
                        kind: .category,
                        key: RawKey.sleepAnalysis.rawValue,
                        hkIdentifier: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
                        uuid: sample.uuid.uuidString,
                        start: ISO8601.zonedString(sample.startDate, timeZone: timeZone),
                        end: ISO8601.zonedString(sample.endDate, timeZone: timeZone),
                        value: nil,
                        unit: nil,
                        categoryValue: sample.value,
                        categoryLabel: Self.sleepLabel(sample.value),
                        workoutActivityType: nil,
                        durationSec: nil,
                        totalEnergyKcal: nil,
                        totalDistanceM: nil,
                        components: nil,
                        componentUnits: nil,
                        sourceBundleId: source.bundleIdentifier,
                        sourceName: source.name,
                        deviceModel: device?.model,
                        deviceManufacturer: device?.manufacturer,
                        wasUserEntered: wasUserEntered
                    )
                )
            }

            return (status: .ok, entries: entries)
        } catch {
            return (status: Self.mapToMetricStatus(error) ?? .unauthorized, entries: [])
        }
    }

    private func exportWorkoutSamples(
        day: DayWindow,
        timeZone: TimeZone
    ) async -> (status: MetricStatus, entries: [(start: Date, record: RawSampleRecord)]) {
        let type = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])

        do {
            let workouts: [HKWorkout] = try await sampleQuery(
                type: type,
                predicate: predicate,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
                ]
            )

            guard !workouts.isEmpty else {
                return (status: .no_data, entries: [])
            }

            let entries = workouts.map { workout -> (start: Date, record: RawSampleRecord) in
                let source = workout.sourceRevision.source
                let device = workout.device
                let wasUserEntered = workout.metadata?[HKMetadataKeyWasUserEntered] as? Bool

                return (
                    start: workout.startDate,
                    record: RawSampleRecord(
                        kind: .workout,
                        key: RawKey.workout.rawValue,
                        hkIdentifier: type.identifier,
                        uuid: workout.uuid.uuidString,
                        start: ISO8601.zonedString(workout.startDate, timeZone: timeZone),
                        end: ISO8601.zonedString(workout.endDate, timeZone: timeZone),
                        value: nil,
                        unit: nil,
                        categoryValue: nil,
                        categoryLabel: nil,
                        workoutActivityType: Int(workout.workoutActivityType.rawValue),
                        durationSec: workout.duration,
                        totalEnergyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        totalDistanceM: workout.totalDistance?.doubleValue(for: .meter()),
                        components: nil,
                        componentUnits: nil,
                        sourceBundleId: source.bundleIdentifier,
                        sourceName: source.name,
                        deviceModel: device?.model,
                        deviceManufacturer: device?.manufacturer,
                        wasUserEntered: wasUserEntered
                    )
                )
            }

            return (status: .ok, entries: entries)
        } catch {
            return (status: Self.mapToMetricStatus(error) ?? .unauthorized, entries: [])
        }
    }

    private static func sleepLabel(_ raw: Int) -> String? {
        switch raw {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            "in_bed"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            "asleep_unspecified"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            "asleep_core"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            "asleep_deep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            "asleep_rem"
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            "awake"
        default:
            nil
        }
    }

    private func queryCumulativeSum(type: HKQuantityType, unit: HKUnit, day: DayWindow) async -> MetricResult {
        do {
            let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [.strictStartDate, .strictEndDate])
            let quantity = try await statistics(
                type: type,
                predicate: predicate,
                options: .cumulativeSum
            ) { $0.sumQuantity() }

            guard let quantity else {
                return MetricResult(value: nil, status: .no_data, unit: MetricKey.steps.unitString)
            }

            return MetricResult(value: quantity.doubleValue(for: unit), status: .ok, unit: MetricKey.steps.unitString)
        } catch {
            if let status = Self.mapToMetricStatus(error) {
                return MetricResult(value: nil, status: status, unit: MetricKey.steps.unitString)
            }
            return MetricResult(value: nil, status: .unauthorized, unit: MetricKey.steps.unitString)
        }
    }

    private func queryDiscreteAverage(
        type: HKQuantityType,
        unit: HKUnit,
        unitString: String,
        day: DayWindow,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> MetricResult {
        do {
            let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [.strictStartDate, .strictEndDate])
            let quantity = try await statistics(
                type: type,
                predicate: predicate,
                options: .discreteAverage
            ) { $0.averageQuantity() }

            guard let quantity else {
                return MetricResult(value: nil, status: .no_data, unit: unitString)
            }

            return MetricResult(value: transform(quantity.doubleValue(for: unit)), status: .ok, unit: unitString)
        } catch {
            if let status = Self.mapToMetricStatus(error) {
                return MetricResult(value: nil, status: status, unit: unitString)
            }
            return MetricResult(value: nil, status: .unauthorized, unit: unitString)
        }
    }

    private func queryLatestQuantity(
        type: HKQuantityType,
        unit: HKUnit,
        unitString: String,
        day: DayWindow,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> MetricResult {
        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])

        do {
            let samples: [HKQuantitySample] = try await sampleQuery(
                type: type,
                predicate: predicate,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false),
                    NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false),
                ],
                limit: 1
            )

            guard let sample = samples.first else {
                return MetricResult(value: nil, status: .no_data, unit: unitString)
            }

            return MetricResult(
                value: transform(sample.quantity.doubleValue(for: unit)),
                status: .ok,
                unit: unitString
            )
        } catch {
            if let status = Self.mapToMetricStatus(error) {
                return MetricResult(value: nil, status: status, unit: unitString)
            }
            return MetricResult(value: nil, status: .unauthorized, unit: unitString)
        }
    }

    private func queryLatestBloodPressure(day: DayWindow) async -> BloodPressureResults {
        let systolicFallback = MetricResult(value: nil, status: .unsupported, unit: MetricKey.bloodPressureSystolicMmhg.unitString)
        let diastolicFallback = MetricResult(value: nil, status: .unsupported, unit: MetricKey.bloodPressureDiastolicMmhg.unitString)

        guard let type = HKObjectType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return BloodPressureResults(systolic: systolicFallback, diastolic: diastolicFallback)
        }

        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])

        do {
            let samples: [HKCorrelation] = try await sampleQuery(
                type: type,
                predicate: predicate,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false),
                    NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false),
                ],
                limit: 1
            )

            guard let sample = samples.first,
                  let systolicSample = sample.objects(for: systolicType).first as? HKQuantitySample,
                  let diastolicSample = sample.objects(for: diastolicType).first as? HKQuantitySample else {
                return BloodPressureResults(
                    systolic: MetricResult(value: nil, status: .no_data, unit: MetricKey.bloodPressureSystolicMmhg.unitString),
                    diastolic: MetricResult(value: nil, status: .no_data, unit: MetricKey.bloodPressureDiastolicMmhg.unitString)
                )
            }

            return BloodPressureResults(
                systolic: MetricResult(
                    value: systolicSample.quantity.doubleValue(for: Self.pressureUnit),
                    status: .ok,
                    unit: MetricKey.bloodPressureSystolicMmhg.unitString
                ),
                diastolic: MetricResult(
                    value: diastolicSample.quantity.doubleValue(for: Self.pressureUnit),
                    status: .ok,
                    unit: MetricKey.bloodPressureDiastolicMmhg.unitString
                )
            )
        } catch {
            let status = Self.mapToMetricStatus(error) ?? .unauthorized
            return BloodPressureResults(
                systolic: MetricResult(value: nil, status: status, unit: MetricKey.bloodPressureSystolicMmhg.unitString),
                diastolic: MetricResult(value: nil, status: status, unit: MetricKey.bloodPressureDiastolicMmhg.unitString)
            )
        }
    }

    private struct SleepResults {
        let asleep: MetricResult
        let inBed: MetricResult
    }

    private func querySleepMinutes(type: HKCategoryType, day: DayWindow) async -> SleepResults {
        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])

        do {
            let samples: [HKCategorySample] = try await sampleQuery(type: type, predicate: predicate, sortDescriptors: [
                NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
            ])

            guard !samples.isEmpty else {
                return SleepResults(
                    asleep: MetricResult(value: nil, status: .no_data, unit: MetricKey.sleepAsleepMinutes.unitString),
                    inBed: MetricResult(value: nil, status: .no_data, unit: MetricKey.sleepInBedMinutes.unitString)
                )
            }

            var asleepSeconds: TimeInterval = 0
            var inBedSeconds: TimeInterval = 0
            var sawAsleep = false
            var sawInBed = false

            for sample in samples {
                let overlapStart = max(day.start, sample.startDate)
                let overlapEnd = min(day.end, sample.endDate)
                let seconds = max(0, overlapEnd.timeIntervalSince(overlapStart))
                if seconds <= 0 { continue }

                let value = sample.value
                if Self.sleepAsleepValues.contains(value) {
                    sawAsleep = true
                    asleepSeconds += seconds
                }
                if value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                    sawInBed = true
                    inBedSeconds += seconds
                }
            }

            let asleepMinutes = asleepSeconds / 60.0
            let inBedMinutes = inBedSeconds / 60.0

            let asleepResult: MetricResult = if sawAsleep {
                MetricResult(value: asleepMinutes, status: .ok, unit: MetricKey.sleepAsleepMinutes.unitString)
            } else {
                MetricResult(value: nil, status: .no_data, unit: MetricKey.sleepAsleepMinutes.unitString)
            }

            let inBedResult: MetricResult = if sawInBed {
                MetricResult(value: inBedMinutes, status: .ok, unit: MetricKey.sleepInBedMinutes.unitString)
            } else {
                MetricResult(value: nil, status: .no_data, unit: MetricKey.sleepInBedMinutes.unitString)
            }

            return SleepResults(asleep: asleepResult, inBed: inBedResult)
        } catch {
            if let status = Self.mapToMetricStatus(error) {
                return SleepResults(
                    asleep: MetricResult(value: nil, status: status, unit: MetricKey.sleepAsleepMinutes.unitString),
                    inBed: MetricResult(value: nil, status: status, unit: MetricKey.sleepInBedMinutes.unitString)
                )
            }

            return SleepResults(
                asleep: MetricResult(value: nil, status: .unauthorized, unit: MetricKey.sleepAsleepMinutes.unitString),
                inBed: MetricResult(value: nil, status: .unauthorized, unit: MetricKey.sleepInBedMinutes.unitString)
            )
        }
    }

    private static let sleepAsleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]

    private struct AnchoredBatch {
        let samples: [HKSample]
        let deletedObjects: [HKDeletedObject]
        let newAnchor: HKQueryAnchor?
    }

    private struct AnchoredOutcome {
        let anchorData: Data?
        let trackedSamples: [String: TrackedSampleState]
        let affectedDates: Set<String>
        let addedSamples: Int
        let deletedSamples: Int
        let unknownDeletedSamples: Int
    }

    private func collectAnchoredChanges(
        type: HKSampleType,
        state: AnchoredTypeState,
        timeZone: TimeZone
    ) async throws -> AnchoredOutcome {
        var trackedSamples = state.trackedSamples
        var affectedDates: Set<String> = []
        var addedSamples = 0
        var deletedSamples = 0
        var unknownDeletedSamples = 0
        var anchor = Self.unarchiveAnchor(state.anchorData)

        while true {
            let batch = try await anchoredQuery(type: type, anchor: anchor, limit: Self.anchoredBatchSize)
            if let newAnchor = batch.newAnchor {
                anchor = newAnchor
            }

            for deleted in batch.deletedObjects {
                let uuid = deleted.uuid.uuidString
                if let existing = trackedSamples.removeValue(forKey: uuid) {
                    if state.isPrimed {
                        deletedSamples += 1
                        affectedDates.formUnion(existing.dates)
                    }
                } else if state.isPrimed {
                    unknownDeletedSamples += 1
                }
            }

            for sample in batch.samples {
                let tracked = Self.trackedSampleState(for: sample, timeZone: timeZone)
                trackedSamples[sample.uuid.uuidString] = tracked

                if state.isPrimed {
                    addedSamples += 1
                    affectedDates.formUnion(tracked.dates)
                }
            }

            if batch.samples.count + batch.deletedObjects.count < Self.anchoredBatchSize {
                break
            }
        }

        return AnchoredOutcome(
            anchorData: Self.archiveAnchor(anchor),
            trackedSamples: trackedSamples,
            affectedDates: affectedDates,
            addedSamples: addedSamples,
            deletedSamples: deletedSamples,
            unknownDeletedSamples: unknownDeletedSamples
        )
    }

    private func statistics(
        type: HKQuantityType,
        predicate: NSPredicate,
        options: HKStatisticsOptions,
        select: @Sendable @escaping (HKStatistics) -> HKQuantity?
    ) async throws -> HKQuantity? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let statistics else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: select(statistics))
            }
            store.execute(query)
        }
    }

    private func sampleQuery<T: HKSample>(
        type: HKSampleType,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor],
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [T]) ?? [])
            }
            store.execute(query)
        }
    }

    private static func mapToMetricStatus(_ error: Error) -> MetricStatus? {
        let ns = error as NSError
        if ns.domain == HKErrorDomain {
            switch ns.code {
            case HKError.errorAuthorizationDenied.rawValue,
                 HKError.errorAuthorizationNotDetermined.rawValue:
                return .unauthorized
            case HKError.errorHealthDataUnavailable.rawValue,
                 HKError.errorHealthDataRestricted.rawValue:
                return .unsupported
            default:
                return nil
            }
        }

        return nil
    }

    private func enableBackgroundDelivery(
        for type: HKObjectType,
        frequency: HKUpdateFrequency
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: HKErrorDomain,
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "HealthKit refused background delivery."]
                    ))
                }
            }
        }
    }

    private func anchoredQuery(
        type: HKSampleType,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredBatch {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: limit) { _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: AnchoredBatch(
                    samples: samples ?? [],
                    deletedObjects: deletedObjects ?? [],
                    newAnchor: newAnchor
                ))
            }
            store.execute(query)
        }
    }

    private static func trackedSampleState(for sample: HKSample, timeZone: TimeZone) -> TrackedSampleState {
        TrackedSampleState(dates: Array(affectedDates(for: sample, timeZone: timeZone)).sorted())
    }

    private static func affectedDates(for sample: HKSample, timeZone: TimeZone) -> Set<String> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let startDay = calendar.startOfDay(for: sample.startDate)
        let effectiveEnd = sample.endDate > sample.startDate
            ? sample.endDate.addingTimeInterval(-0.001)
            : sample.startDate
        let endDay = calendar.startOfDay(for: effectiveEnd)

        var dates: Set<String> = []
        var cursor = startDay
        while cursor <= endDay {
            dates.insert(DateFormatting.ymdString(from: cursor, in: timeZone))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private static func archiveAnchor(_ anchor: HKQueryAnchor?) -> Data? {
        guard let anchor else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    private static func unarchiveAnchor(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func unsupportedRevision(
        for date: Date,
        timeZone: TimeZone,
        collector: CollectorIdentity,
        generatedAt: Date,
        commitId: String,
        rawManifestRelpath: String
    ) -> DailyRevision {
        let dayWindow = dayWindow(for: date, timeZone: timeZone)
        let ymd = DateFormatting.ymdString(from: date, in: timeZone)
        let dayPayload = DayPayload(
            timezone: timeZone.identifier,
            start: ISO8601.zonedString(dayWindow.start, timeZone: timeZone),
            end: ISO8601.zonedString(dayWindow.end, timeZone: timeZone)
        )

        var metrics: [String: Double?] = [:]
        var metricStatus: [String: MetricStatus] = [:]
        var metricUnits: [String: String] = [:]

        for key in MetricKey.allCases {
            metrics[key.rawValue] = nil
            metricStatus[key.rawValue] = .unsupported
            metricUnits[key.rawValue] = key.unitString
        }

        return DailyRevision(
            schemaVersion: "health.daily.v1",
            commitId: commitId,
            date: ymd,
            day: dayPayload,
            generatedAt: ISO8601.utcString(generatedAt),
            collector: CollectorPayload(collectorId: collector.collectorId, deviceId: collector.deviceId),
            metrics: metrics,
            metricStatus: metricStatus,
            metricUnits: metricUnits,
            rawManifestRelpath: rawManifestRelpath
        )
    }
}
