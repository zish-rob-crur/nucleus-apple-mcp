import SwiftUI
import WidgetKit

private enum WidgetPalette {
    static let accent = Color(red: 0.42, green: 0.72, blue: 0.56)
    static let accentDeep = Color(red: 0.24, green: 0.48, blue: 0.37)
    static let warning = Color(red: 0.84, green: 0.62, blue: 0.24)
    static let danger = Color(red: 0.79, green: 0.38, blue: 0.36)

    static let foreground = Color(red: 0.95, green: 0.96, blue: 0.94)
    static let secondary = Color(red: 0.84, green: 0.87, blue: 0.85).opacity(0.76)
    static let tertiary = Color(red: 0.80, green: 0.84, blue: 0.81).opacity(0.46)

    static let backgroundTop = Color(red: 0.15, green: 0.17, blue: 0.17)
    static let backgroundBottom = Color(red: 0.10, green: 0.11, blue: 0.12)
    static let stroke = Color(red: 0.80, green: 0.88, blue: 0.84).opacity(0.12)
    static let badgeFill = Color(red: 0.92, green: 0.96, blue: 0.93).opacity(0.08)
    static let warmGlow = Color(red: 0.72, green: 0.58, blue: 0.47).opacity(0.10)
}

private struct NucleusSyncEntry: TimelineEntry {
    let date: Date
    let snapshot: NucleusActivitySnapshot
}

private struct NucleusSyncProvider: TimelineProvider {
    func placeholder(in context: Context) -> NucleusSyncEntry {
        NucleusSyncEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NucleusSyncEntry) -> Void) {
        completion(NucleusSyncEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NucleusSyncEntry>) -> Void) {
        let now = Date()
        let entry = NucleusSyncEntry(date: now, snapshot: snapshot)
        let refreshMinutes = snapshot.phase == .syncing ? 5 : 30
        let refresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: now)
            ?? now.addingTimeInterval(Double(refreshMinutes * 60))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private var snapshot: NucleusActivitySnapshot {
        NucleusActivityStore.load()
    }
}

struct NucleusSyncStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NucleusSharedState.widgetKind, provider: NucleusSyncProvider()) { entry in
            NucleusSyncWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Sync")
        .description("See your latest Nucleus sync in small, medium, or large sizes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct NucleusSyncWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: NucleusSyncEntry

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            header

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: detailSpacing) {
                Text(entry.snapshot.widgetTitle)
                    .font(.system(size: titleSize, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Text(entry.snapshot.widgetDetail)
                    .font(.system(detailFont, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(detailLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            phaseRule

            if !metaItems.isEmpty {
                metaLine(metaItems)
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            WidgetBackground(statusTint: statusTint, family: family)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.snapshot.headerLine)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(WidgetPalette.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 7, height: 7)

                Text(entry.snapshot.badgeLabel)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(statusTint.opacity(0.94))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(WidgetPalette.badgeFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(statusTint.opacity(0.16), lineWidth: 1)
                    )
            }
        }
    }

    private var phaseRule: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))

            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                statusTint.opacity(0.94),
                                statusTint.opacity(0.58),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(proxy.size.width * entry.snapshot.phaseTrackValue, 16))
            }
        }
        .frame(height: 4)
    }

    private func metaLine(_ items: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Circle()
                        .fill(WidgetPalette.tertiary)
                        .frame(width: 3, height: 3)
                }

                Text(item)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 0)
        }
    }

    private var metaItems: [String] {
        let limit: Int = switch family {
        case .systemSmall:
            1
        case .systemMedium:
            2
        case .systemLarge:
            3
        default:
            2
        }

        return Array(entry.snapshot.widgetMetaItems.prefix(limit))
    }

    private var contentPadding: CGFloat {
        switch family {
        case .systemSmall:
            16
        case .systemMedium:
            18
        case .systemLarge:
            20
        default:
            16
        }
    }

    private var verticalSpacing: CGFloat {
        switch family {
        case .systemSmall:
            11
        case .systemMedium:
            13
        case .systemLarge:
            15
        default:
            12
        }
    }

    private var detailSpacing: CGFloat {
        switch family {
        case .systemSmall:
            5
        case .systemMedium:
            6
        case .systemLarge:
            7
        default:
            6
        }
    }

    private var titleSize: CGFloat {
        switch family {
        case .systemSmall:
            25
        case .systemMedium:
            31
        case .systemLarge:
            35
        default:
            28
        }
    }

    private var detailFont: Font.TextStyle {
        switch family {
        case .systemSmall:
            .footnote
        case .systemMedium:
            .subheadline
        case .systemLarge:
            .subheadline
        default:
            .footnote
        }
    }

    private var detailLineLimit: Int {
        switch family {
        case .systemSmall:
            2
        case .systemMedium:
            2
        case .systemLarge:
            3
        default:
            2
        }
    }

    private var statusTint: Color {
        switch entry.snapshot.phase {
        case .ready:
            WidgetPalette.accentDeep
        case .syncing:
            WidgetPalette.accent
        case .needsAuthorization:
            WidgetPalette.warning
        case .setup:
            WidgetPalette.foreground.opacity(0.68)
        case .error:
            WidgetPalette.danger
        }
    }
}

private struct WidgetBackground: View {
    let statusTint: Color
    let family: WidgetFamily

    var body: some View {
        let cornerRadius = switch family {
        case .systemSmall:
            28.0
        case .systemMedium:
            32.0
        case .systemLarge:
            36.0
        default:
            28.0
        }

        ZStack {
            LinearGradient(
                colors: [WidgetPalette.backgroundTop, WidgetPalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    statusTint.opacity(0.18),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: family == .systemLarge ? 220 : 170
            )

            Ellipse()
                .fill(WidgetPalette.warmGlow)
                .frame(width: family == .systemSmall ? 88 : 140, height: family == .systemSmall ? 42 : 68)
                .blur(radius: family == .systemSmall ? 22 : 30)
                .offset(x: family == .systemSmall ? 18 : 34, y: family == .systemLarge ? 88 : 52)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(WidgetPalette.stroke, lineWidth: 1)
        }
    }
}

private extension NucleusActivitySnapshot {
    var badgeLabel: String {
        switch phase {
        case .ready:
            "Ready"
        case .syncing:
            "Live"
        case .needsAuthorization:
            "Action"
        case .setup:
            "Setup"
        case .error:
            "Review"
        }
    }

    var headerLine: String {
        switch phase {
        case .ready:
            if let lastSyncAt {
                return "Last sync \(Self.clockString(for: lastSyncAt))"
            }
            return "Ready to sync"
        case .syncing:
            return "Updated \(Self.shortRelativeString(for: lastUpdatedAt))"
        case .needsAuthorization:
            return "Health access needed"
        case .setup:
            return "Set up the first export"
        case .error:
            return isStorageError ? "Storage needs setup" : "Latest sync needs review"
        }
    }

    var widgetTitle: String {
        switch phase {
        case .ready:
            return "Synced"
        case .syncing:
            return "Syncing"
        case .needsAuthorization:
            return "Health Access"
        case .setup:
            return "First Sync"
        case .error:
            return isStorageError ? "Storage Setup" : "Needs Review"
        }
    }

    var widgetDetail: String {
        switch phase {
        case .ready:
            return "Your latest export is current."
        case .syncing:
            return "Refreshing your recent export."
        case .needsAuthorization:
            return "Grant access to keep exports current."
        case .setup:
            return "Choose how much history to import."
        case .error:
            return isStorageError ? "Choose where exports should be saved." : "Open Nucleus to review the latest sync."
        }
    }

    var widgetMetaItems: [String] {
        switch phase {
        case .ready:
            var items: [String] = [storageLabel]
            if let lastSyncAt {
                items.append(Self.clockString(for: lastSyncAt))
            }
            items.append(syncModeLabel)
            return items
        case .syncing:
            return [syncModeLabel, uploadLabel, "Updated \(Self.shortRelativeString(for: lastUpdatedAt))"]
        case .needsAuthorization, .setup, .error:
            return []
        }
    }

    var phaseTrackValue: Double {
        switch phase {
        case .ready:
            1
        case .syncing:
            0.72
        case .needsAuthorization:
            0.22
        case .setup:
            0.16
        case .error:
            0.30
        }
    }

    private var isStorageError: Bool {
        errorMessage?.localizedCaseInsensitiveContains("storage") == true
    }

    private static func shortRelativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func clockString(for date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
