import SwiftUI

enum NucleusPalette {
    static let accent = Color(red: 0.42, green: 0.72, blue: 0.56)
    static let accentDeep = Color(red: 0.24, green: 0.48, blue: 0.37)
    static let warning = Color(red: 0.84, green: 0.62, blue: 0.24)
    static let danger = Color(red: 0.79, green: 0.38, blue: 0.36)
    static let ink = Color(red: 0.06, green: 0.07, blue: 0.08)
    static let graphite = Color(red: 0.12, green: 0.14, blue: 0.14)
    static let paper = Color(red: 0.98, green: 0.98, blue: 0.96)
    static let fog = Color(red: 0.92, green: 0.95, blue: 0.93)
    static let mist = Color(red: 0.66, green: 0.75, blue: 0.71).opacity(0.10)
    static let mistStrong = Color(red: 0.78, green: 0.84, blue: 0.81).opacity(0.18)

    static func accentForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accent : accentDeep
    }
}

enum NucleusStyle {
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.17, blue: 0.16).opacity(0.76)
            : NucleusPalette.paper.opacity(0.76)
    }

    static func surfaceStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.16, green: 0.19, blue: 0.18).opacity(0.90)
            : Color.white.opacity(0.90)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.74, green: 0.82, blue: 0.78).opacity(0.16)
            : Color(red: 0.27, green: 0.36, blue: 0.33).opacity(0.10)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.30)
            : Color(red: 0.11, green: 0.14, blue: 0.13).opacity(0.10)
    }
}

struct NucleusBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDecorations = false

    var body: some View {
        ZStack {
            baseGradient

            if showDecorations {
                decorativeLayers
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .task {
            guard !showDecorations else { return }
            guard !reduceMotion else {
                showDecorations = true
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                showDecorations = true
            }
        }
    }

    @ViewBuilder
    private var baseGradient: some View {
        if colorScheme == .dark {
            LinearGradient(colors: [
                NucleusPalette.ink,
                Color(red: 0.08, green: 0.10, blue: 0.09),
                NucleusPalette.graphite,
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(colors: [
                NucleusPalette.paper,
                Color(red: 0.95, green: 0.97, blue: 0.95),
                NucleusPalette.fog,
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var decorativeLayers: some View {
        if colorScheme == .dark {
            NucleusAurora()

            RadialGradient(
                colors: [
                    NucleusPalette.accent.opacity(0.14),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )

            NucleusGrid()
                .opacity(0.08)
                .blendMode(.overlay)

            NucleusScanlines()
                .opacity(0.03)
                .blendMode(.overlay)
        } else {
            NucleusAurora()
                .opacity(0.14)
                .blendMode(.screen)

            RadialGradient(
                colors: [
                    NucleusPalette.accent.opacity(0.04),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 460
            )

            NucleusGrid()
                .opacity(0.03)
                .blendMode(.normal)
        }
    }
}

struct NucleusAurora: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            let primary = NucleusPalette.accent.opacity(colorScheme == .dark ? 0.42 : 0.20)
            let secondary = NucleusPalette.accentDeep.opacity(colorScheme == .dark ? 0.18 : 0.08)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [primary, secondary, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 620, height: 620)
                .blur(radius: 110)
                .offset(x: 260, y: -260)

            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.10),
                            NucleusPalette.accentDeep.opacity(colorScheme == .dark ? 0.16 : 0.08),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 520, height: 380)
                .blur(radius: 80)
                .rotationEffect(.degrees(-16))
                .offset(x: -180, y: 260)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NucleusGrid: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 26
            var path = Path()

            for x in stride(from: 0, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for y in stride(from: 0, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            let lineColor = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
            context.stroke(path, with: .color(lineColor), lineWidth: 0.6)

            var glow = Path()
            glow.addRect(CGRect(origin: .zero, size: size).insetBy(dx: 0.3, dy: 0.3))
            let glowColor = NucleusPalette.accent.opacity(colorScheme == .dark ? 0.12 : 0.05)
            context.stroke(glow, with: .color(glowColor), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NucleusScanlines: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 3.0
            let lineWidth: CGFloat = 0.6
            var y: CGFloat = 0
            var index = 0
            while y <= size.height {
                let alpha: Double = (index % 2 == 0) ? 0.12 : 0.05
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                let base = colorScheme == .dark ? Color.white : Color.black
                context.stroke(path, with: .color(base.opacity(colorScheme == .dark ? alpha : alpha * 0.6)), lineWidth: lineWidth)
                y += step
                index += 1
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NucleusCard<Content: View>: View {
    private let title: String
    private let systemImage: String?
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(NucleusPalette.accentForeground(colorScheme).opacity(0.9))
                        .frame(width: 18)
                }

                Text(title.uppercased())
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(colorScheme == .dark ? 0.92 : 0.88))
                    .tracking(1.25)

                Spacer(minLength: 0)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NucleusCardBackground())
    }
}

struct NucleusCardBackground: View {
    var cornerRadius: CGFloat = 26
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill = colorScheme == .dark
            ? Color(red: 0.11, green: 0.14, blue: 0.13).opacity(0.88)
            : Color.white.opacity(0.78)
        let mist = colorScheme == .dark ? NucleusPalette.mist : Color.white.opacity(0.34)
        let mistStrong = colorScheme == .dark ? NucleusPalette.mistStrong : Color(red: 0.30, green: 0.38, blue: 0.35).opacity(0.10)
        let accentStroke = NucleusPalette.accent.opacity(colorScheme == .dark ? 0.10 : 0.05)
        let materialOpacity = colorScheme == .dark ? 0.18 : 0.42

        shape
            .fill(fill)
            .overlay(
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(materialOpacity)
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.46),
                                Color.white.opacity(colorScheme == .dark ? 0.01 : 0.16),
                                Color.black.opacity(colorScheme == .dark ? 0.20 : 0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            mistStrong,
                            mist,
                            mistStrong,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .overlay(
                shape.strokeBorder(accentStroke, lineWidth: 1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: NucleusStyle.shadow(colorScheme), radius: 16, x: 0, y: 10)
    }
}

struct NucleusInset<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NucleusStyle.surfaceStrong(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NucleusStyle.stroke(colorScheme), lineWidth: 1)
            )
    }
}

struct SyncProgressPanel: View {
    let progress: SyncProgress

    var body: some View {
        NucleusInset {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let contextLabel = progress.contextLabel {
                            Text(contextLabel.uppercased())
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(NucleusPalette.accent.opacity(0.88))
                                .tracking(0.8)
                        }

                        Text(progress.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(progress.detail)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    StatusPill(label: progress.phaseLabel, kind: .neutral, systemImage: progress.phaseIcon)
                }

                if let dateLabel = progress.dateProgressLabel,
                   let dateValue = progress.dateProgressValue {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Dates")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.secondary)
                            Spacer(minLength: 0)
                            Text(dateLabel)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Color.secondary)
                        }

                        ProgressView(value: dateValue)
                            .tint(NucleusPalette.accent)
                    }
                } else {
                    ProgressView()
                        .tint(NucleusPalette.accent)
                }

                if let uploadLabel = progress.uploadProgressLabel,
                   let uploadValue = progress.uploadProgressValue {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Uploads")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.secondary)
                            Spacer(minLength: 0)
                            Text(uploadLabel)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Color.secondary)
                        }

                        ProgressView(value: uploadValue)
                            .tint(Color.primary.opacity(0.75))
                    }
                }
            }
        }
    }
}

struct SyncProgressOverlay: View {
    let progress: SyncProgress
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let baseFill = colorScheme == .dark
            ? NucleusPalette.graphite.opacity(0.96)
            : NucleusPalette.paper.opacity(0.94)
        let materialOpacity = colorScheme == .dark ? 0.16 : 0.40

        SyncProgressPanel(progress: progress)
            .padding(4)
            .background {
                shape
                    .fill(baseFill)
                    .overlay(
                        shape
                            .fill(.ultraThinMaterial)
                            .opacity(materialOpacity)
                    )
                    .overlay(
                        shape
                            .stroke(NucleusStyle.stroke(colorScheme), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        NucleusPalette.accent.opacity(colorScheme == .dark ? 0.95 : 0.78),
                                        NucleusPalette.accentDeep.opacity(colorScheme == .dark ? 0.75 : 0.52),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 124, height: 4)
                            .padding(.top, 10)
                            .padding(.leading, 16)
                    }
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 18, y: 8)
            .shadow(color: NucleusPalette.accent.opacity(colorScheme == .dark ? 0.06 : 0.02), radius: 14, y: 3)
    }
}

struct NucleusTerminal<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(colorScheme == .dark ? Color.black.opacity(0.24) : NucleusPalette.fog.opacity(0.82))
                    .overlay(
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24),
                                        .clear,
                                        Color.black.opacity(colorScheme == .dark ? 0.30 : 0.06),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.overlay)
                    )
                    .overlay(
                        shape.stroke(NucleusStyle.stroke(colorScheme), lineWidth: 1)
                    )
            )
    }
}

struct NucleusTileBackground: View {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    init(tint: Color = Color.white.opacity(0.12)) {
        self.tint = tint
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        shape
            .fill(NucleusStyle.surfaceStrong(colorScheme))
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.28),
                                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.10),
                                Color.black.opacity(colorScheme == .dark ? 0.22 : 0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            )
            .overlay(
                shape.stroke(NucleusStyle.stroke(colorScheme), lineWidth: 1)
            )
            .overlay(
                shape.stroke(tint.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: colorScheme == .dark ? Color.black.opacity(0.18) : Color.black.opacity(0.08), radius: 14, x: 0, y: 10)
    }
}

struct StatusPill: View {
    enum Kind {
        case ok
        case neutral
        case warning
        case error
    }

    let label: String
    let kind: Kind
    var systemImage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }

            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .tracking(0.25)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
                .opacity(colorScheme == .dark ? 0.55 : 0.45)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.10) : Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }

    private var foreground: Color {
        switch kind {
        case .ok: colorScheme == .dark ? NucleusPalette.accent : NucleusPalette.accentDeep
        case .neutral: Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.78)
        case .warning: NucleusPalette.warning
        case .error: NucleusPalette.danger
        }
    }

    private var background: Color {
        switch kind {
        case .ok: NucleusPalette.accent.opacity(colorScheme == .dark ? 0.14 : 0.09)
        case .neutral: NucleusStyle.surfaceStrong(colorScheme)
        case .warning: NucleusPalette.warning.opacity(colorScheme == .dark ? 0.14 : 0.10)
        case .error: NucleusPalette.danger.opacity(colorScheme == .dark ? 0.14 : 0.10)
        }
    }

    private var border: Color {
        switch kind {
        case .ok: NucleusPalette.accent.opacity(0.20)
        case .neutral: NucleusStyle.stroke(colorScheme)
        case .warning: NucleusPalette.warning.opacity(0.18)
        case .error: NucleusPalette.danger.opacity(0.18)
        }
    }
}

struct NucleusOrb: View {
    enum State {
        case idle
        case syncing
        case needsPermission
        case error
    }

    let state: State
    var size: CGFloat = 84
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @SwiftUI.State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.10))
                .blur(radius: 10)

            Circle()
                .fill(RadialGradient(colors: glowColors, center: .center, startRadius: 2, endRadius: 90))
                .blur(radius: 0)
                .overlay(
                    Circle()
                        .strokeBorder(
                            AngularGradient(colors: ringColors, center: .center),
                            lineWidth: 1.2
                        )
                        .opacity(0.85)
                )
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                        .blur(radius: 0.2)
                )
                .scaleEffect(reduceMotion ? 1 : (breathe ? 1.02 : 0.98))
                .animation(animation, value: breathe)

            if state == .syncing {
                ProgressView()
                    .tint(Color.primary.opacity(colorScheme == .dark ? 0.9 : 0.7))
            }
        }
        .frame(width: size, height: size)
        .onAppear { breathe = !reduceMotion }
        .accessibilityLabel(accessibilityText)
    }

    private var animation: Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        switch state {
        case .syncing:
            return .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        case .error:
            return .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
        default:
            return .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
        }
    }

    private var glowColors: [Color] {
        switch state {
        case .idle:
            [
                NucleusPalette.accent.opacity(colorScheme == .dark ? 0.40 : 0.18),
                NucleusPalette.accentDeep.opacity(colorScheme == .dark ? 0.12 : 0.04),
                .clear,
            ]
        case .syncing:
            [NucleusPalette.accentDeep.opacity(colorScheme == .dark ? 0.34 : 0.14), NucleusPalette.accent.opacity(0.12), .clear]
        case .needsPermission:
            [NucleusPalette.warning.opacity(0.42), .clear]
        case .error:
            [NucleusPalette.danger.opacity(0.42), .clear]
        }
    }

    private var ringColors: [Color] {
        switch state {
        case .idle:
            if colorScheme == .dark {
                [NucleusPalette.accent.opacity(0.20), Color.white.opacity(0.06), NucleusPalette.accentDeep.opacity(0.18)]
            } else {
                [NucleusPalette.accent.opacity(0.10), Color.white.opacity(0.16), NucleusPalette.accentDeep.opacity(0.08)]
            }
        case .syncing:
            [NucleusPalette.accentDeep.opacity(colorScheme == .dark ? 0.18 : 0.10), NucleusPalette.accent.opacity(0.20), Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)]
        case .needsPermission:
            [NucleusPalette.warning.opacity(0.20), Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)]
        case .error:
            [NucleusPalette.danger.opacity(0.20), Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)]
        }
    }

    private var accessibilityText: Text {
        switch state {
        case .idle: Text("Idle")
        case .syncing: Text("Syncing")
        case .needsPermission: Text("Needs Permission")
        case .error: Text("Error")
        }
    }
}

struct NucleusButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case ghost
    }

    let kind: Kind
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let cornerRadius: CGFloat = 16
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(foreground(configuration))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                background(configuration, shape: shape)
            }
            .overlay {
                shape.stroke(border(configuration), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private func foreground(_ configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return colorScheme == .dark ? NucleusPalette.ink : Color(red: 0.09, green: 0.11, blue: 0.10)
        case .secondary:
            return Color.primary.opacity(configuration.isPressed ? 0.78 : 0.88)
        case .ghost:
            return Color.primary.opacity(configuration.isPressed ? 0.72 : 0.82)
        }
    }

    @ViewBuilder
    private func background(_ configuration: Configuration, shape: RoundedRectangle) -> some View {
        switch kind {
        case .primary:
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            NucleusPalette.accent.opacity(configuration.isPressed ? 0.84 : 0.96),
                            NucleusPalette.accentDeep.opacity(configuration.isPressed ? 0.78 : 0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.24 : 0.34),
                                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12),
                                    .clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.overlay)
                        .opacity(configuration.isPressed ? 0.30 : 0.62)
                )
                .shadow(color: NucleusPalette.accent.opacity(configuration.isPressed ? 0.04 : 0.10), radius: 10, x: 0, y: 6)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 10, x: 0, y: 6)
        case .secondary:
            shape
                .fill(NucleusStyle.surfaceStrong(colorScheme).opacity(configuration.isPressed ? 0.88 : 1.0))
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.24),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.overlay)
                        .opacity(configuration.isPressed ? 0.30 : 0.55)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.10 : 0.05), radius: 8, x: 0, y: 4)
        case .ghost:
            shape
                .fill(configuration.isPressed ? NucleusStyle.surface(colorScheme).opacity(0.90) : Color.clear)
        }
    }

    private func border(_ configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return NucleusPalette.accentDeep.opacity(configuration.isPressed ? 0.28 : 0.18)
        case .secondary:
            return NucleusStyle.stroke(colorScheme).opacity(configuration.isPressed ? 0.95 : 0.85)
        case .ghost:
            return NucleusStyle.stroke(colorScheme).opacity(0.78)
        }
    }
}

struct NucleusInlineStat: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.secondary)
                .tracking(1.1)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NucleusStyle.surfaceStrong(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NucleusStyle.stroke(colorScheme), lineWidth: 1)
        )
    }
}

struct NucleusErrorCallout: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NucleusPalette.danger)
                .font(.system(.callout, design: .rounded).weight(.semibold))

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(NucleusPalette.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NucleusPalette.danger.opacity(0.18), lineWidth: 1)
        )
    }
}

struct NucleusWarningCallout: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(NucleusPalette.warning)
                .font(.system(.callout, design: .rounded).weight(.semibold))

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(NucleusPalette.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NucleusPalette.warning.opacity(0.18), lineWidth: 1)
        )
    }
}

struct NucleusSuccessCallout: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(NucleusPalette.accent)
                .font(.system(.callout, design: .rounded).weight(.semibold))

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(NucleusPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NucleusPalette.accent.opacity(0.18), lineWidth: 1)
        )
    }
}
