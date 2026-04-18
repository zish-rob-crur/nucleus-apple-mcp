import Foundation

enum MetricStatus: String, Codable {
    case ok
    case no_data
    case unauthorized
    case unsupported
}

enum MetricKey: String, CaseIterable, Identifiable {
    case steps
    case activeEnergyKcal = "active_energy_kcal"
    case exerciseMinutes = "exercise_minutes"
    case standHours = "stand_hours"
    case restingHrAvg = "resting_hr_avg"
    case hrvSdnnAvg = "hrv_sdnn_avg"
    case vo2Max = "vo2_max"
    case oxygenSaturationPct = "oxygen_saturation_pct"
    case respiratoryRateAvg = "respiratory_rate_avg"
    case wristTemperatureCelsius = "wrist_temperature_celsius"
    case bodyMassKg = "body_mass_kg"
    case bodyFatPercentage = "body_fat_percentage"
    case bloodPressureSystolicMmhg = "blood_pressure_systolic_mmhg"
    case bloodPressureDiastolicMmhg = "blood_pressure_diastolic_mmhg"
    case bloodGlucoseMgDl = "blood_glucose_mg_dl"
    case bodyTemperatureCelsius = "body_temperature_celsius"
    case basalBodyTemperatureCelsius = "basal_body_temperature_celsius"
    case sleepAsleepMinutes = "sleep_asleep_minutes"
    case sleepInBedMinutes = "sleep_in_bed_minutes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steps: "Steps"
        case .activeEnergyKcal: "Active Energy"
        case .exerciseMinutes: "Exercise"
        case .standHours: "Stand"
        case .restingHrAvg: "Resting HR"
        case .hrvSdnnAvg: "HRV (SDNN)"
        case .vo2Max: "VO₂ Max"
        case .oxygenSaturationPct: "SpO₂"
        case .respiratoryRateAvg: "Respiratory"
        case .wristTemperatureCelsius: "Wrist Temp Δ"
        case .bodyMassKg: "Weight"
        case .bodyFatPercentage: "Body Fat"
        case .bloodPressureSystolicMmhg: "BP Systolic"
        case .bloodPressureDiastolicMmhg: "BP Diastolic"
        case .bloodGlucoseMgDl: "Blood Glucose"
        case .bodyTemperatureCelsius: "Body Temp"
        case .basalBodyTemperatureCelsius: "Basal Temp"
        case .sleepAsleepMinutes: "Sleep (Asleep)"
        case .sleepInBedMinutes: "Sleep (In Bed)"
        }
    }

    var unitString: String {
        switch self {
        case .steps: "count"
        case .activeEnergyKcal: "kcal"
        case .exerciseMinutes: "min"
        case .standHours: "hr"
        case .restingHrAvg: "bpm"
        case .hrvSdnnAvg: "ms"
        case .vo2Max: "mL/kg/min"
        case .oxygenSaturationPct: "%"
        case .respiratoryRateAvg: "brpm"
        case .wristTemperatureCelsius: "Δ°C"
        case .bodyMassKg: "kg"
        case .bodyFatPercentage: "%"
        case .bloodPressureSystolicMmhg: "mmHg"
        case .bloodPressureDiastolicMmhg: "mmHg"
        case .bloodGlucoseMgDl: "mg/dL"
        case .bodyTemperatureCelsius: "°C"
        case .basalBodyTemperatureCelsius: "°C"
        case .sleepAsleepMinutes: "min"
        case .sleepInBedMinutes: "min"
        }
    }

    var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .activeEnergyKcal: "flame.fill"
        case .exerciseMinutes: "figure.run"
        case .standHours: "figure.stand"
        case .restingHrAvg: "heart.fill"
        case .hrvSdnnAvg: "waveform.path.ecg"
        case .vo2Max: "lungs.fill"
        case .oxygenSaturationPct: "drop.fill"
        case .respiratoryRateAvg: "wind"
        case .wristTemperatureCelsius: "thermometer.medium"
        case .bodyMassKg: "scalemass.fill"
        case .bodyFatPercentage: "figure.arms.open"
        case .bloodPressureSystolicMmhg: "waveform.path"
        case .bloodPressureDiastolicMmhg: "waveform.path"
        case .bloodGlucoseMgDl: "drop.triangle.fill"
        case .bodyTemperatureCelsius: "thermometer.high"
        case .basalBodyTemperatureCelsius: "thermometer.low"
        case .sleepAsleepMinutes: "moon.zzz"
        case .sleepInBedMinutes: "bed.double.fill"
        }
    }
}

struct DayWindow {
    let timeZone: TimeZone
    let start: Date
    let end: Date
}

struct DayPayload: Codable {
    let timezone: String
    let start: String
    let end: String
}

struct CollectorPayload: Codable {
    let collectorId: String
    let deviceId: String

    enum CodingKeys: String, CodingKey {
        case collectorId = "collector_id"
        case deviceId = "device_id"
    }
}

struct DailyRevision: Codable {
    let schemaVersion: String
    let commitId: String
    let date: String
    let day: DayPayload
    let generatedAt: String
    let collector: CollectorPayload
    let metrics: [String: Double?]
    let metricStatus: [String: MetricStatus]
    let metricUnits: [String: String]
    let rawManifestRelpath: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case commitId = "commit_id"
        case date
        case day
        case generatedAt = "generated_at"
        case collector
        case metrics
        case metricStatus = "metric_status"
        case metricUnits = "metric_units"
        case rawManifestRelpath = "raw_manifest_relpath"
    }
}

struct DailyMonthIndex: Codable {
    let schemaVersion: String
    let month: String
    let generatedAt: String
    let days: [DailyRevision]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case month
        case generatedAt = "generated_at"
        case days
    }
}

struct MetricResult: Equatable {
    let value: Double?
    let status: MetricStatus
    let unit: String
}

struct CollectorIdentity: Equatable {
    let collectorId: String
    let deviceId: String
}

enum RevisionId {
    static func generate(now: Date = Date(), randomHexLength: Int = 6) -> String {
        let utc = ISO8601DateFormatter()
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        utc.formatOptions = [.withInternetDateTime]

        let timestamp = utc.string(from: now)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        // Example: 20260208T100000Z

        let suffix = (0..<max(6, randomHexLength))
            .map { _ in "0123456789ABCDEF".randomElement()! }
            .reduce(into: "") { $0.append($1) }

        return "\(timestamp)-\(suffix)"
    }
}

enum ISO8601 {
    static func utcString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func zonedString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

enum DateFormatting {
    static func ymdString(from date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from ymd: String, in timeZone: TimeZone) -> Date? {
        guard let components = ymdComponents(from: ymd) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: components.year,
            month: components.month,
            day: components.day
        ))
    }

    static func ymdComponents(from ymd: String) -> (year: Int, month: Int, day: Int)? {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return nil
        }
        return (y, m, d)
    }

    static func recentYMDStrings(endingAt now: Date, days: Int, timeZone: TimeZone) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)

        return (0..<max(1, days)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return ymdString(from: date, in: timeZone)
        }
    }
}

enum RawSampleKind: String, Encodable {
    case quantity
    case category
    case workout
    case correlation
}

struct RawSamplesMeta: Encodable {
    let date: String
    let day: DayPayload
    let generatedAt: String
    let collector: CollectorPayload
    let typeStatus: [String: MetricStatus]
    let typeCounts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case date
        case day
        case generatedAt = "generated_at"
        case collector
        case typeStatus = "type_status"
        case typeCounts = "type_counts"
    }
}

struct RawSampleRecord: Encodable {
    let record: String = "sample"
    let kind: RawSampleKind
    let key: String
    let hkIdentifier: String
    let uuid: String
    let start: String
    let end: String

    let value: Double?
    let unit: String?

    let categoryValue: Int?
    let categoryLabel: String?

    let workoutActivityType: Int?
    let durationSec: Double?
    let totalEnergyKcal: Double?
    let totalDistanceM: Double?
    let components: [String: Double]?
    let componentUnits: [String: String]?

    let sourceBundleId: String?
    let sourceName: String?
    let deviceModel: String?
    let deviceManufacturer: String?
    let wasUserEntered: Bool?

    enum CodingKeys: String, CodingKey {
        case record
        case kind
        case key
        case hkIdentifier = "hk_identifier"
        case uuid
        case start
        case end
        case value
        case unit
        case categoryValue = "category_value"
        case categoryLabel = "category_label"
        case workoutActivityType = "workout_activity_type"
        case durationSec = "duration_sec"
        case totalEnergyKcal = "total_energy_kcal"
        case totalDistanceM = "total_distance_m"
        case components
        case componentUnits = "component_units"
        case sourceBundleId = "source_bundle_id"
        case sourceName = "source_name"
        case deviceModel = "device_model"
        case deviceManufacturer = "device_manufacturer"
        case wasUserEntered = "was_user_entered"
    }
}

struct RawSamplesExport {
    let meta: RawSamplesMeta
    let samples: [RawSampleRecord]
}

struct RawTypeFile: Codable {
    let status: MetricStatus
    let recordCount: Int
    let relpath: String?

    enum CodingKeys: String, CodingKey {
        case status
        case recordCount = "record_count"
        case relpath
    }
}

struct RawSamplesManifest: Codable {
    let schemaVersion: String
    let commitId: String
    let date: String
    let day: DayPayload
    let generatedAt: String
    let collector: CollectorPayload
    let types: [String: RawTypeFile]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case commitId = "commit_id"
        case date
        case day
        case generatedAt = "generated_at"
        case collector
        case types
    }
}

struct HealthCommitDateChange: Codable {
    let date: String
    let dailyRelpath: String
    let monthRelpath: String
    let rawManifestRelpath: String
    let rawTypeKeys: [String]

    enum CodingKeys: String, CodingKey {
        case date
        case dailyRelpath = "daily_relpath"
        case monthRelpath = "month_relpath"
        case rawManifestRelpath = "raw_manifest_relpath"
        case rawTypeKeys = "raw_type_keys"
    }
}

struct HealthSyncCommit: Codable {
    let schemaVersion: String
    let commitId: String
    let generatedAt: String
    let collector: CollectorPayload
    let dates: [HealthCommitDateChange]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case commitId = "commit_id"
        case generatedAt = "generated_at"
        case collector
        case dates
    }
}
