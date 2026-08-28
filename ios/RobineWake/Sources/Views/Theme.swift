import SwiftUI

enum RobineTheme {
    static let night950 = Color(red: 7 / 255, green: 9 / 255, blue: 20 / 255)
    static let night900 = Color(red: 13 / 255, green: 16 / 255, blue: 34 / 255)
    static let night850 = Color(red: 18 / 255, green: 22 / 255, blue: 44 / 255)
    static let night800 = Color(red: 24 / 255, green: 29 / 255, blue: 55 / 255)
    static let text = Color(red: 247 / 255, green: 245 / 255, blue: 1)
    static let muted = Color(red: 169 / 255, green: 173 / 255, blue: 199 / 255)
    static let moon = Color(red: 245 / 255, green: 207 / 255, blue: 135 / 255)
    static let moonSoft = Color(red: 1, green: 231 / 255, blue: 183 / 255)
    static let lavender = Color(red: 170 / 255, green: 167 / 255, blue: 1)
    static let mint = Color(red: 120 / 255, green: 217 / 255, blue: 188 / 255)
    static let rose = Color(red: 1, green: 140 / 255, blue: 163 / 255)
    static let breathingInhaleAmber = Color(red: 245 / 255, green: 183 / 255, blue: 91 / 255)
    static let breathingExhaleRose = Color(red: 224 / 255, green: 105 / 255, blue: 143 / 255)
    static let twilightRose = Color(red: 224 / 255, green: 105 / 255, blue: 143 / 255)
}

struct NightBackground: View {
    private let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.08, 0.09, 2, 0.42), (0.18, 0.21, 1.5, 0.7), (0.31, 0.07, 1, 0.55),
        (0.44, 0.17, 2, 0.8), (0.62, 0.08, 1.5, 0.5), (0.79, 0.16, 1, 0.8),
        (0.91, 0.05, 2, 0.55), (0.13, 0.37, 1, 0.65), (0.72, 0.32, 1.5, 0.48),
        (0.92, 0.43, 1, 0.75), (0.25, 0.55, 1.5, 0.4), (0.83, 0.61, 2, 0.42),
        (0.06, 0.72, 1, 0.65), (0.52, 0.75, 1.5, 0.4), (0.94, 0.84, 1, 0.65)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [RobineTheme.night950, RobineTheme.night900, RobineTheme.night850],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [RobineTheme.lavender.opacity(0.14), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.85
                )

                Canvas { context, size in
                    for (x, y, radius, opacity) in stars {
                        let rect = CGRect(
                            x: size.width * x,
                            y: size.height * y,
                            width: radius,
                            height: radius
                        )
                        context.opacity = opacity
                        context.fill(Path(ellipseIn: rect), with: .color(RobineTheme.moonSoft))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct CrescentMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "moon.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [RobineTheme.moonSoft, RobineTheme.moon],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: RobineTheme.moon.opacity(0.32), radius: size * 0.35)
            .accessibilityHidden(true)
    }
}

struct RobineCardModifier: ViewModifier {
    var padding: CGFloat = 18
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(highlighted ? RobineTheme.night800.opacity(0.94) : RobineTheme.night850.opacity(0.88))
                    .stroke(
                        highlighted ? RobineTheme.lavender.opacity(0.42) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
            )
    }
}

extension View {
    func robineCard(padding: CGFloat = 18, highlighted: Bool = false) -> some View {
        modifier(RobineCardModifier(padding: padding, highlighted: highlighted))
    }

    func robineScreen() -> some View {
        foregroundStyle(RobineTheme.text)
            .tint(RobineTheme.lavender)
            .scrollContentBackground(.hidden)
            .background(NightBackground())
            .preferredColorScheme(.dark)
    }
}

struct SectionEyebrow: View {
    let text: String
    var color = RobineTheme.lavender

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

struct StatusPill: View {
    let title: String
    let connected: Bool
    let busy: Bool

    var body: some View {
        HStack(spacing: 7) {
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .tint(RobineTheme.moon)
            } else {
                Circle()
                    .fill(connected ? RobineTheme.mint : RobineTheme.rose)
                    .frame(width: 7, height: 7)
                    .shadow(color: connected ? RobineTheme.mint : RobineTheme.rose, radius: 5)
            }
            Text(busy ? "Synchronisation" : title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.1)))
    }
}

struct MetricRow: View {
    let icon: String
    let title: String
    let detail: String
    var color = RobineTheme.lavender

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(RobineTheme.muted)
        }
    }
}
