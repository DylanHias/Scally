import SwiftUI

/// Design tokens transcribed from docs/design/2026-09-20-flow-board.md.
///
/// Both themes are designed, so every colour is a dynamic pair rather than a
/// single value with opacity applied. Values are verbatim from the design; do
/// not "improve" them here - change the design and re-transcribe.
enum Palette {
    static let background = dynamic(dark: 0x0B0B0C, light: 0xF6F6F7)
    static let surface = dynamic(dark: 0x141417, light: 0xFFFFFF)
    static let surfaceRaised = dynamic(dark: 0x1C1C1F, light: 0xFBFBFA)
    static let border = dynamic(dark: 0x2A2A2F, light: 0xEFEFF1)
    static let primaryText = dynamic(dark: 0xF5F5F7, light: 0x1A1A1A)
    static let accent = dynamic(dark: 0xE2A45E, light: 0xA8641F)
    static let destructive = dynamic(dark: 0xD4675C, light: 0xB3392C)

    static var secondaryText: Color { primaryText.opacity(0.55) }
    static var tertiaryText: Color { primaryText.opacity(0.38) }

    private static func dynamic(dark: Int, light: Int) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Numbers, dimensions and byte counts are monospaced throughout, so columns of
/// figures line up and a changing value does not reflow its row.
enum Typography {
    static let screenTitle = Font.system(size: 22, weight: .semibold)
    static let sectionLabel = Font.system(size: 11, weight: .semibold).monospaced()
    static let body = Font.system(size: 15)
    static let metric = Font.system(size: 14, weight: .medium).monospaced()
    static let metricLarge = Font.system(size: 44, weight: .medium).monospaced()
    static let caption = Font.system(size: 12)
    static let badge = Font.system(size: 11, weight: .bold).monospaced()
}

enum Metrics {
    static let control: CGFloat = 12
    static let card: CGFloat = 14
    static let sheet: CGFloat = 22
    static let gutter: CGFloat = 20
}

/// The uppercase monospaced field captions the design uses for INPUT, OUTPUT,
/// ESTIMATE, ENGINE, NETWORK and RECENT.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typography.sectionLabel)
            .tracking(0.9)
            .foregroundStyle(Palette.secondaryText)
    }
}

/// A scale badge: 2x or 4x.
struct ScaleBadge: View {
    let scale: Int

    var body: some View {
        Text("\(scale)×")
            .font(Typography.badge)
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.accent.opacity(0.14), in: Capsule())
    }
}

/// One INPUT / OUTPUT / ESTIMATE row: caption left, monospaced value right.
struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            FieldLabel(label)
            Spacer(minLength: 16)
            Text(value)
                .font(Typography.metric)
                .foregroundStyle(Palette.primaryText)
        }
    }
}
