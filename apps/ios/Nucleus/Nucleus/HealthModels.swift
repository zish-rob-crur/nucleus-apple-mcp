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
    let date: String
    let day: DayPayload
    let generatedAt: String
    let collector: CollectorPayload
    let metrics: [String: Double?]
    let metricStatus: [String: MetricStatus]
    let metricUnits: [String: String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case date
        case day
        case generatedAt = "generated_at"
        case collector
        case metrics
        case metricStatus = "metric_status"
        case metricUnits = "metric_units"
    }
}

struct LatestPointer: Codable {
    let date: String
    let latestGeneratedAt: String
    let revisionId: String
    let revisionRelpath: String

    enum CodingKeys: String, CodingKey {
        case date
        case latestGeneratedAt = "latest_generated_at"
        case revisionId = "revision_id"
        case revisionRelpath = "revision_relpath"
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
}

enum RawSampleKind: String, Encodable {
    case quantity
    case category
    case workout
}

struct RawSamplesMeta: Encodable {
    let record: String = "meta"
    let schemaVersion: String = "health.raw.v1"
    let date: String
    let day: DayPayload
    let generatedAt: String
    let collector: CollectorPayload
    let typeStatus: [String: MetricStatus]
    let typeCounts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case record
        case schemaVersion = "schema_version"
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
