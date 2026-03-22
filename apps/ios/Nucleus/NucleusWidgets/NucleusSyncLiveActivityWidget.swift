import ActivityKit
import SwiftUI
import WidgetKit

struct NucleusSyncLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NucleusSyncActivityAttributes.self) { context in
            NucleusSyncLiveActivityView(state: context.state)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .activityBackgroundTint(Color(red: 0.10, green: 0.10, blue: 0.12))
                .activitySystemActionForegroundColor(Color.white.opacity(0.84))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(phaseTint(for: context.state.phase))
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)

                            Text("Nucleus")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.86))
                        }

                        Spacer(minLength: 16)

                        Text(phaseBadge(for: context.state.phase))
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.54))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    NucleusSyncLiveActivityCompactContent(state: context.state)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            } compactLeading: {
                Circle()
                    .fill(phaseTint(for: context.state.phase))
                    .frame(width: 9, height: 9)
            } compactTrailing: {
                if let progressValue = context.state.progressValue,
                   context.state.phase != .failed {
                    Text(progressValue, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                } else {
                    Text("!")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(phaseTint(for: context.state.phase))
                }
            } minimal: {
                Circle()
                    .fill(phaseTint(for: context.state.phase))
                    .frame(width: 8, height: 8)
            }
            .widgetURL(URL(string: "nucleus://sync"))
            .keylineTint(keylineTint(for: context.state.phase))
        }
    }

    private func phaseBadge(for phase: NucleusSyncLivePhase) -> String {
        switch phase {
        case .planning:
            "Preparing"
        case .collecting, .uploading, .finalizing:
            "Syncing"
        case .completed:
            "Complete"
        case .failed:
            "Review"
        }
    }

    private func phaseTint(for phase: NucleusSyncLivePhase) -> Color {
        switch phase {
        case .planning, .collecting, .uploading:
            Color(red: 0.47, green: 0.57, blue: 0.52)
        case .finalizing, .completed:
            Color(red: 0.42, green: 0.47, blue: 0.44)
        case .failed:
            Color(red: 0.63, green: 0.47, blue: 0.44)
        }
    }

    private func keylineTint(for phase: NucleusSyncLivePhase) -> Color {
        switch phase {
        case .failed:
            phaseTint(for: phase).opacity(0.72)
        default:
            Color.white.opacity(0.18)
        }
    }
}

private struct NucleusSyncLiveActivityView: View {
    let state: NucleusSyncActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(phaseTint)
                    .frame(width: 6, height: 6)

                Text("Nucleus")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.74))

                Spacer(minLength: 0)

                Text(statusLabel)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            Text(headline)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(primaryLine)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let secondaryLabel = state.secondaryLabel {
                    Text(secondaryLabel)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.38))
                }
            }

            if let progressValue = state.progressValue, state.phase != .failed {
                quietProgressBar(progressValue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var phaseTint: Color {
        switch state.phase {
        case .planning, .collecting, .uploading:
            Color(red: 0.47, green: 0.57, blue: 0.52)
        case .finalizing, .completed:
            Color(red: 0.42, green: 0.47, blue: 0.44)
        case .failed:
            Color(red: 0.63, green: 0.47, blue: 0.44)
        }
    }

    private var statusLabel: String {
        switch state.phase {
        case .planning:
            "Preparing"
        case .collecting, .uploading, .finalizing:
            "In Progress"
        case .completed:
            "Complete"
        case .failed:
            "Needs Review"
        }
    }

    private var headline: String {
        switch state.phase {
        case .failed:
            "Sync needs review"
        case .finalizing:
            "Finishing export"
        default:
            "Syncing your export"
        }
    }

    private var primaryLine: String {
        switch state.phase {
        case .failed:
            state.detail
        case .finalizing:
            state.progressLabel ?? "Saving latest revision"
        default:
            state.progressLabel ?? state.detail
        }
    }

    @ViewBuilder
    private func quietProgressBar(_ progressValue: Double) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * progressValue, 20)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(phaseTint.opacity(0.86))
                    .frame(width: width)
            }
        }
        .frame(height: 3)
    }
}

private struct NucleusSyncLiveActivityCompactContent: View {
    let state: NucleusSyncActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(headline)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let progressLabel = state.progressLabel {
                    Text(progressLabel)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                } else {
                    Text(headline)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let secondaryLabel = state.secondaryLabel {
                    Text(secondaryLabel)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.36))
                        .lineLimit(1)
                }
            }

            if let progressValue = state.progressValue, state.phase != .failed {
                GeometryReader { proxy in
                    let width = max(proxy.size.width * progressValue, 20)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))

                        Capsule()
                            .fill(phaseTint.opacity(0.86))
                            .frame(width: width)
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phaseTint: Color {
        switch state.phase {
        case .planning, .collecting, .uploading:
            Color(red: 0.47, green: 0.57, blue: 0.52)
        case .finalizing, .completed:
            Color(red: 0.42, green: 0.47, blue: 0.44)
        case .failed:
            Color(red: 0.63, green: 0.47, blue: 0.44)
        }
    }

    private var headline: String {
        switch state.phase {
        case .failed:
            "Sync needs review"
        case .finalizing:
            "Finishing export"
        default:
            "Syncing your export"
        }
    }
}
