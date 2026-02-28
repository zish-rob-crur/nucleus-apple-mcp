import SwiftUI

enum NucleusPalette {
    static let accent = Color(red: 0.36, green: 0.96, blue: 0.76)
    static let accentDeep = Color(red: 0.14, green: 0.80, blue: 0.62)
    static let warning = Color(red: 0.98, green: 0.80, blue: 0.30)
    static let danger = Color(red: 0.98, green: 0.38, blue: 0.46)
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.07)
    static let graphite = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let mist = Color.white.opacity(0.06)
    static let mistStrong = Color.white.opacity(0.10)
}

enum NucleusStyle {
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }

    static func surfaceStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.12)
    }
}

struct NucleusBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(colors: [
                    NucleusPalette.ink,
                    Color(red: 0.04, green: 0.07, blue: 0.08),
                    NucleusPalette.graphite,
                ], startPoint: .topLeading, endPoint: .bottomTrailing)

                NucleusAurora()

                RadialGradient(
                    colors: [
                        NucleusPalette.accent.opacity(0.22),
                        .clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 460
                )

                NucleusGrid()
                    .opacity(0.12)
                    .blendMode(.overlay)

                NucleusScanlines()
                    .opacity(0.07)
                    .blendMode(.overlay)
            } else {
                LinearGradient(colors: [
                    Color(red: 0.97, green: 0.99, blue: 0.99),
                    Color(red: 0.93, green: 0.97, blue: 0.97),
                    Color(red: 0.90, green: 0.95, blue: 0.96),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)

                NucleusAurora()
                    .opacity(0.55)
                    .blendMode(.screen)

                RadialGradient(
                    colors: [
                        NucleusPalette.accent.opacity(0.16),
                        .clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 520
                )

                NucleusGrid()
                    .opacity(0.10)
                    .blendMode(.normal)

                NucleusScanlines()
                    .opacity(0.035)
                    .blendMode(.overlay)
            }
        }
        .ignoresSafeArea()
    }
}

struct NucleusAurora: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [NucleusPalette.accent.opacity(0.70), NucleusPalette.accentDeep.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 620, height: 620)
                .blur(radius: 90)
                .offset(x: 260, y: -260)

            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            NucleusPalette.accent.opacity(0.10),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 520, height: 380)
                .blur(radius: 80)
                .rotationEffect(.degrees(-18))
                .offset(x: -180, y: 260)
        }
        .blendMode(colorScheme == .dark ? .plusLighter : .screen)
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

            let lineColor = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
            context.stroke(path, with: .color(lineColor), lineWidth: 0.6)

            var glow = Path()
            glow.addRect(CGRect(origin: .zero, size: size).insetBy(dx: 0.3, dy: 0.3))
            let glowColor = NucleusPalette.accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
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
                        .foregroundStyle(NucleusPalette.accent.opacity(0.9))
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
    var cornerRadius: CGFloat = 22
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let mist = colorScheme == .dark ? NucleusPalette.mist : Color.black.opacity(0.06)
        let mistStrong = colorScheme == .dark ? NucleusPalette.mistStrong : Color.black.opacity(0.10)
        let material: Material = colorScheme == .dark ? .ultraThinMaterial : .thinMaterial

        shape
            .fill(material)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.09 : 0.65),
                        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.25),
                        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
                shape.strokeBorder(NucleusPalette.accent.opacity(0.16), lineWidth: 1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: NucleusStyle.shadow(colorScheme), radius: 20, x: 0, y: 14)
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
            .background(NucleusStyle.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NucleusStyle.stroke(colorScheme), lineWidth: 1)
            )
    }
}

struct NucleusTerminal<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(colorScheme == .dark ? Color.black.opacity(0.26) : Color.black.opacity(0.05))
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18),
                                .clear,
                                Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
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
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        shape
            .fill(NucleusStyle.surface(colorScheme))
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55),
                        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.22),
                        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.overlay)
            )
            .overlay(
                shape.stroke(NucleusStyle.stroke(colorScheme), lineWidth: 1)
            )
            .overlay(
                shape.stroke(tint.opacity(0.22), lineWidth: 1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: colorScheme == .dark ? Color.black.opacity(0.18) : Color.black.opacity(0.10), radius: 16, x: 0, y: 12)
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
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }

            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.22 : 0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
                .opacity(0.75)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.10), radius: 10, x: 0, y: 8)
    }

    private var foreground: Color {
        switch kind {
        case .ok: NucleusPalette.accent
        case .neutral: Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.78)
        case .warning: NucleusPalette.warning
        case .error: NucleusPalette.danger
        }
    }

    private var background: Color {
        switch kind {
        case .ok: NucleusPalette.accent.opacity(0.10)
        case .neutral: NucleusStyle.surface(colorScheme)
        case .warning: NucleusPalette.warning.opacity(0.10)
        case .error: NucleusPalette.danger.opacity(0.10)
        }
    }

    private var border: Color {
        switch kind {
        case .ok: NucleusPalette.accent.opacity(0.25)
        case .neutral: NucleusStyle.stroke(colorScheme)
        case .warning: NucleusPalette.warning.opacity(0.22)
        case .error: NucleusPalette.danger.opacity(0.22)
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
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                        .blur(radius: 0.2)
                )
                .scaleEffect(breathe ? 1.02 : 0.98)
                .animation(animation, value: breathe)

            if state == .syncing {
                ProgressView()
                    .tint(Color.primary.opacity(colorScheme == .dark ? 0.9 : 0.7))
            }
        }
        .frame(width: size, height: size)
        .onAppear { breathe = true }
        .accessibilityLabel(accessibilityText)
    }

    private var animation: Animation {
        switch state {
        case .syncing:
            .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        case .error:
            .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
        default:
            .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
        }
    }

    private var glowColors: [Color] {
        switch state {
        case .idle:
            [NucleusPalette.accent.opacity(0.55), NucleusPalette.accent.opacity(0.10), .clear]
        case .syncing:
            [Color.primary.opacity(colorScheme == .dark ? 0.65 : 0.35), NucleusPalette.accent.opacity(0.18), .clear]
        case .needsPermission:
            [NucleusPalette.warning.opacity(0.55), .clear]
        case .error:
            [NucleusPalette.danger.opacity(0.55), .clear]
        }
    }

    private var ringColors: [Color] {
        switch state {
        case .idle:
            [NucleusPalette.accent.opacity(0.30), Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), NucleusPalette.accent.opacity(0.22)]
        case .syncing:
            [Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.16), NucleusPalette.accent.opacity(0.28), Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)]
        case .needsPermission:
            [NucleusPalette.warning.opacity(0.28), Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)]
        case .error:
            [NucleusPalette.danger.opacity(0.28), Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)]
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
            .padding(.vertical, 11)
            .background {
                background(configuration, shape: shape)
            }
            .overlay {
                shape.stroke(border(configuration), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }

    private func foreground(_ configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return NucleusPalette.ink
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
                            NucleusPalette.accent.opacity(configuration.isPressed ? 0.82 : 1.0),
                            NucleusPalette.accentDeep.opacity(configuration.isPressed ? 0.72 : 0.95),
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
                                    Color.white.opacity(colorScheme == .dark ? 0.34 : 0.40),
                                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.14),
                                    .clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.overlay)
                        .opacity(configuration.isPressed ? 0.35 : 0.75)
                )
                .shadow(color: NucleusPalette.accent.opacity(configuration.isPressed ? 0.10 : 0.22), radius: 18, x: 0, y: 14)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 18, x: 0, y: 14)
        case .secondary:
            shape
                .fill(NucleusStyle.surface(colorScheme).opacity(configuration.isPressed ? 0.85 : 1.0))
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.30),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.overlay)
                        .opacity(configuration.isPressed ? 0.35 : 0.70)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 14, x: 0, y: 10)
        case .ghost:
            shape
                .fill(configuration.isPressed ? NucleusStyle.surface(colorScheme) : Color.clear)
        }
    }

    private func border(_ configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return Color.black.opacity(configuration.isPressed ? 0.22 : 0.18)
        case .secondary:
            return NucleusStyle.stroke(colorScheme).opacity(configuration.isPressed ? 0.95 : 0.85)
        case .ghost:
            return NucleusStyle.stroke(colorScheme)
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
        .background(NucleusStyle.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(NucleusPalette.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NucleusPalette.danger.opacity(0.22), lineWidth: 1)
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
        .background(NucleusPalette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NucleusPalette.warning.opacity(0.22), lineWidth: 1)
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
        .background(NucleusPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NucleusPalette.accent.opacity(0.22), lineWidth: 1)
        )
    }
}
