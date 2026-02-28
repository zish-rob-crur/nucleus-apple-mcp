import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                logsCard

                footer
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NucleusBackground())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
            .environmentObject(AppModel())
    }
}

private extension DiagnosticsView {
    var summaryCard: some View {
        NucleusCard("Summary", systemImage: "stethoscope") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    NucleusInlineStat(title: "Logs", value: "\(model.logs.count)")
                    NucleusInlineStat(title: "S3", value: model.objectStoreSettings.enabled ? "enabled" : "off")
                    NucleusInlineStat(title: "Auth", value: authShortLabel)
                }

                if let error = model.lastError {
                    NucleusErrorCallout(message: error)
                } else {
                    Text("No errors recorded.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    var logsCard: some View {
        NucleusCard("Logs", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        model.clearLogs()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .ghost))

                    Spacer(minLength: 0)

                    Button {
                        UIPasteboard.general.string = model.logs.map { "\($0.timestamp): \($0.level.rawValue) \($0.message)" }.joined(separator: "\n")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(NucleusButtonStyle(kind: .ghost))
                    .disabled(model.logs.isEmpty)
                }

                if model.logs.isEmpty {
                    NucleusTerminal {
                        Text("No logs yet.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .padding(.vertical, 6)
                    }
                } else {
                    NucleusTerminal {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.logs.prefix(24)) { line in
                                LogRow(line: line)
                            }
                        }
                    }
                }
            }
        }
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "ladybug.fill")
                .foregroundStyle(Color.secondary.opacity(0.85))
            Text("If something looks wrong, copy logs and the latest exported file paths.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .opacity(0.92)
    }

    var authShortLabel: String {
        switch model.authRequestStatus {
        case .unnecessary:
            "ready"
        case .shouldRequest:
            "needs"
        case .unknown:
            "unknown"
        @unknown default:
            "unknown"
        }
    }
}

private struct LogRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 0)

            Text(line.timestamp.formatted(.dateTime.hour().minute().second()))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Text(line.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch line.level {
        case .info:
            Color.secondary.opacity(0.85)
        case .success:
            NucleusPalette.accent
        case .error:
            NucleusPalette.danger
        }
    }
}
