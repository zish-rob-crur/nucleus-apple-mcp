import ActivityKit
import Foundation

enum NucleusLiveActivityController {
    static func upsert(progress: SyncProgress) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard progress.phase != .planning else { return }

        let content = ActivityContent(
            state: NucleusSyncActivityAttributes.ContentState(progress: progress),
            staleDate: nil
        )

        if let activity = Activity<NucleusSyncActivityAttributes>.activities.first {
            await activity.update(content)
            return
        }

        do {
            _ = try Activity.request(
                attributes: NucleusSyncActivityAttributes(name: "Nucleus"),
                content: content,
                pushType: nil
            )
        } catch {
        }
    }

    static func end(snapshot: NucleusActivitySnapshot, failed: Bool) async {
        guard let activity = Activity<NucleusSyncActivityAttributes>.activities.first else { return }

        if failed {
            let finalState = NucleusSyncActivityAttributes.ContentState.failed(snapshot.errorMessage)
            await activity.end(
                ActivityContent(
                    state: finalState,
                    staleDate: Date().addingTimeInterval(2 * 60)
                ),
                dismissalPolicy: .after(Date().addingTimeInterval(2 * 60))
            )
            return
        }

        await activity.end(nil, dismissalPolicy: .immediate)
    }
}

private extension NucleusSyncActivityAttributes.ContentState {
    static func completed(_ snapshot: NucleusActivitySnapshot) -> Self {
        Self(
            phase: .completed,
            title: "Sync Complete",
            detail: snapshot.lastSyncAt == nil ? "Your latest export is ready." : snapshot.detail,
            progressValue: 1,
            progressLabel: snapshot.metaLine,
            secondaryLabel: snapshot.shortRevision.map { "Revision \($0)" }
        )
    }

    static func failed(_ message: String?) -> Self {
        Self(
            phase: .failed,
            title: "Sync Failed",
            detail: message ?? "The latest sync needs review in the app.",
            progressValue: nil,
            progressLabel: nil,
            secondaryLabel: nil
        )
    }

    init(progress: SyncProgress) {
        self.phase = switch progress.phase {
        case .planning: .planning
        case .collecting: .collecting
        case .uploading: .uploading
        case .finalizing: .finalizing
        }
        self.title = progress.title
        self.detail = progress.detail
        self.progressValue = progress.liveActivityProgressValue
        self.progressLabel = progress.liveActivityProgressLabel
        self.secondaryLabel = progress.currentDate
    }
}

private extension SyncProgress {
    var liveActivityProgressValue: Double? {
        switch phase {
        case .planning:
            return 0.05
        case .collecting:
            return dateProgressValue.map { max($0, 0.10) }
        case .uploading:
            guard totalDates > 0 else { return uploadProgressValue }
            let base = Double(completedDates) / Double(totalDates)
            let currentWeight = 1 / Double(totalDates)
            return min(base + currentWeight * (uploadProgressValue ?? 0), 0.96)
        case .finalizing:
            return 1
        }
    }

    var liveActivityProgressLabel: String? {
        switch phase {
        case .planning:
            return "Planning"
        case .collecting:
            return dateProgressLabel
        case .uploading:
            return uploadProgressLabel
        case .finalizing:
            return "Finishing up"
        }
    }
}
