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

    private enum RawKey: String, CaseIterable {
        case stepCount = "step_count"
        case activeEnergyBurned = "active_energy_burned"
        case heartRate = "heart_rate"
        case restingHeartRate = "resting_heart_rate"
        case hrvSDNN = "hrv_sdnn"
        case sleepAnalysis = "sleep_analysis"
        case workout = "workout"
    }

    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unknown }

        let readTypes = Self.readTypes
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthCollectorError.healthDataUnavailable }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func makeDailyRevision(
        for date: Date,
        timeZone: TimeZone,
        collector: CollectorIdentity
    ) async throws -> (revision: DailyRevision, generatedAt: Date) {
        guard HKHealthStore.isHealthDataAvailable() else {
            let generatedAt = Date()
            return (
                revision: Self.unsupportedRevision(for: date, timeZone: timeZone, collector: collector, generatedAt: generatedAt),
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
                day: dayWindow
            )
        } else {
            MetricResult(value: nil, status: .unsupported, unit: MetricKey.restingHrAvg.unitString)
        }

        let hrv: MetricResult = if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            await queryDiscreteAverage(
                type: type,
                unit: HKUnit.secondUnit(with: .milli),
                day: dayWindow
            )
        } else {
            MetricResult(value: nil, status: .unsupported, unit: MetricKey.hrvSdnnAvg.unitString)
        }

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
            schemaVersion: "health.v0",
            date: ymd,
            day: dayPayload,
            generatedAt: ISO8601.utcString(generatedAt),
            collector: CollectorPayload(collectorId: collector.collectorId, deviceId: collector.deviceId),
            metrics: metrics,
            metricStatus: metricStatus,
            metricUnits: metricUnits
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

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(activeEnergy) }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(resting) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.activitySummaryType())
        types.insert(HKObjectType.workoutType())
        return types
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
        timeZone: TimeZone
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
                        value: sample.quantity.doubleValue(for: unit),
                        unit: unitString,
                        categoryValue: nil,
                        categoryLabel: nil,
                        workoutActivityType: nil,
                        durationSec: nil,
                        totalEnergyKcal: nil,
                        totalDistanceM: nil,
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

    private func queryDiscreteAverage(type: HKQuantityType, unit: HKUnit, day: DayWindow) async -> MetricResult {
        let unitString: String
        if type.identifier == HKQuantityTypeIdentifier.restingHeartRate.rawValue {
            unitString = MetricKey.restingHrAvg.unitString
        } else {
            unitString = MetricKey.hrvSdnnAvg.unitString
        }

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

            return MetricResult(value: quantity.doubleValue(for: unit), status: .ok, unit: unitString)
        } catch {
            if let status = Self.mapToMetricStatus(error) {
                return MetricResult(value: nil, status: status, unit: unitString)
            }
            return MetricResult(value: nil, status: .unauthorized, unit: unitString)
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
        sortDescriptors: [NSSortDescriptor]
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sortDescriptors) { _, samples, error in
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

    private static func unsupportedRevision(
        for date: Date,
        timeZone: TimeZone,
        collector: CollectorIdentity,
        generatedAt: Date
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
            schemaVersion: "health.v0",
            date: ymd,
            day: dayPayload,
            generatedAt: ISO8601.utcString(generatedAt),
            collector: CollectorPayload(collectorId: collector.collectorId, deviceId: collector.deviceId),
            metrics: metrics,
            metricStatus: metricStatus,
            metricUnits: metricUnits
        )
    }
}
