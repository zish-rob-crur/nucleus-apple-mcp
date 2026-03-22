import ActivityKit
import Foundation

enum NucleusSyncLivePhase: String, Codable, Hashable, Sendable {
    case planning
    case collecting
    case uploading
    case finalizing
    case completed
    case failed
}

struct NucleusSyncActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: NucleusSyncLivePhase
        var title: String
        var detail: String
        var progressValue: Double?
        var progressLabel: String?
        var secondaryLabel: String?
    }

    var name: String
}
