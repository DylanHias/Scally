import SwiftUI

/// Design tokens read from the design itself, not from a summary of it.
///
/// The source is `docs/design/flow-board/Scally - Flow Board.dc.html`, imported
/// from the claude.ai design project on 2026-09-21. Every value below is
/// transcribed from that file's inline styles. The prose extract that preceded
/// it had the light theme's background and surface the wrong way round, among
/// other things, so: change the design and re-import, never "improve" a number
/// here.
enum Palette {
    static let background = dynamic(dark: 0x0B0B0C, light: 0xFFFFFF)
    static let surface = dynamic(dark: 0x141417, light: 0xF6F6F7)
    static let surfaceRaised = dynamic(dark: 0x17171A, light: 0xEFEFF1)
    static let accent = dynamic(dark: 0xE2A45E, light: 0xA8641F)
    static let destructive = dynamic(dark: 0xD4675C, light: 0xB3392C)
    static let primaryText = dynamic(dark: 0xF5F5F7, light: 0x0B0B0C)

    /// The design draws every hairline as 8% of the opposite end of the scale,
    /// never as a solid grey. Rules *between list rows* are 6% - a deliberate
    /// half-step down from the rules that bound a section.
    static var hairline: Color { dynamic(white: 0.08) }
    static var hairlineSoft: Color { dynamic(white: 0.06) }

    /// The well a photo sits in, the segmented control's track and its
    /// selected segment. The design gives each of these its own value per
    /// theme rather than reusing `surface`, and in light the selected segment
    /// is pure white over a grey track - so it cannot be derived.
    static let photoWell = dynamic(dark: 0x141417, light: 0xF2F2F4)
    static let segmentTrack = dynamic(dark: 0x141417, light: 0xEEEEF1)
    static let segmentSelected = dynamic(dark: 0x2A2A2F, light: 0xFFFFFF)

    /// A button outline, at the alpha the design names for that button.
    static func outline(_ alpha: Double) -> Color { dynamic(white: alpha) }

    /// The wash behind a mono badge, and the ring around the Choose a photo
    /// plus.
    static var wash: Color { dynamic(white: 0.10, lightAlpha: 0.07) }
    static var plusRing: Color { dynamic(white: 0.28, lightAlpha: 0.25) }

    /// Secondary text, on the iOS label bases the design uses: 235,235,245 in
    /// dark and 60,60,67 in light. The alpha is the design's own, per use, so
    /// callers pass the number that appears in the markup rather than picking
    /// from a fixed set of three.
    static func label(_ alpha: Double) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: alpha)
                : UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: alpha)
        })
    }

    private static func dynamic(white alpha: Double, lightAlpha: Double? = nil) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: alpha)
                : UIColor(white: 0, alpha: lightAlpha ?? alpha)
        })
    }

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

/// Type, transcribed with the design's own sizes. CSS letter-spacing is in em,
/// so it is converted here: `tracking = em x size`.
enum Typography {
    static let wordmark = Font.system(size: 28, weight: .semibold)
    static let largeTitle = Font.system(size: 26, weight: .semibold)
    static let navAction = Font.system(size: 14)
    static let navTitle = Font.system(size: 12, weight: .regular).monospaced()

    static let rowPrimary = Font.system(size: 16, weight: .semibold)
    static let rowLabel = Font.system(size: 15)
    static let body = Font.system(size: 14)
    static let bodySmall = Font.system(size: 13)

    /// Uppercase mono captions: RECENT, ENGINE, INPUT, ELAPSED.
    static let caption = Font.system(size: 11).monospaced()
    static let captionTiny = Font.system(size: 10).monospaced()
    static let metric = Font.system(size: 12).monospaced()
    static let metricStrong = Font.system(size: 12, weight: .semibold).monospaced()
    static let badge = Font.system(size: 10, weight: .semibold).monospaced()
    static let percent = Font.system(size: 56, weight: .regular)
}

enum Tracking {
    static let wordmark: CGFloat = -0.7   // -.025em x 28
    static let subtitle: CGFloat = 1.1    //  .1em  x 11
    static let sectionLabel: CGFloat = 1.4 //  .14em x 10
}

enum Metrics {
    /// The design's phone is 390 pt wide with a 20 pt content gutter.
    static let gutter: CGFloat = 20
    static let card: CGFloat = 14
    static let control: CGFloat = 14
    static let photo: CGFloat = 16
    static let primaryRowHeight: CGFloat = 60
    static let secondaryRowHeight: CGFloat = 52
    static let buttonHeight: CGFloat = 52
}

/// A hairline rule at the design's 8%, full bleed within its container.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}

/// The uppercase monospaced field captions - RECENT, ENGINE, NETWORK.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typography.captionTiny)
            .tracking(Tracking.sectionLabel)
            .foregroundStyle(Palette.label(0.34))
    }
}

/// The footer rows on Import: ENGINE / NETWORK / STORED LOCALLY. Mono 11 both
/// sides, the label dimmer than the value.
struct TrustRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.label(0.34))
            Spacer(minLength: 8)
            Text(value)
                .font(Typography.caption)
                .foregroundStyle(Palette.label(0.5))
        }
    }
}

/// The 2x / 4x scale badge that sits on a history tile and a recent row.
struct ScaleBadge: View {
    let scale: Int

    var body: some View {
        Text("\(scale)×")
            .font(Typography.badge)
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The committing action - Upscale, Save to Photos, Open Settings. A slab in
/// the primary text colour with the background punched out of it, 54 pt tall.
/// It is deliberately the only filled control in the app.
struct FilledButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.background)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Palette.primaryText, in: RoundedRectangle(cornerRadius: Metrics.control))
    }
}

/// Cancel, Share, Choose specific photos: an outline only, no fill.
struct OutlineButtonLabel: View {
    let title: String
    var height: CGFloat = 52
    var alpha: Double = 0.16
    var size: CGFloat = 17

    var body: some View {
        Text(title)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Palette.primaryText)
            .frame(maxWidth: .infinity, minHeight: height)
            .overlay(RoundedRectangle(cornerRadius: Metrics.control)
                .strokeBorder(Palette.outline(alpha)))
    }
}

/// The top bar on Configure, Processing and Result: an action on the left, a
/// monospaced title centred, and whatever the screen needs on the right. Not a
/// `navigationBar` - iOS 26 renders those as glass capsules that crush a
/// filename to an ellipsis.
struct ScreenBar<Trailing: View>: View {
    let leading: String
    let title: String
    var leadingColor: Color = Palette.label(0.7)
    var titleAlpha: Double = 0.5
    let onLeading: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 11.5).monospaced())
                .tracking(0.69)
                .foregroundStyle(Palette.label(titleAlpha))
                .lineLimit(1)

            HStack {
                Button(leading, action: onLeading)
                    .font(.system(size: 16))
                    .foregroundStyle(leadingColor)
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }
}

/// An INPUT / OUTPUT / ESTIMATE row. `ruled` draws the design's top hairline,
/// which is what separates these rows on Configure but not on Result.
struct DetailRow: View {
    let label: String
    let value: String
    var emphasised = false
    var ruled = false
    var labelAlpha: Double = 0.4
    var valueAlpha: Double = 0.7
    var valueSize: CGFloat = 12.5

    var body: some View {
        VStack(spacing: 0) {
            if ruled { Rectangle().fill(Palette.outline(0.07)).frame(height: 1) }
            HStack(spacing: 12) {
                Text(label)
                    .font(Typography.caption)
                    .tracking(Tracking.subtitle)
                    .foregroundStyle(Palette.label(labelAlpha))
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: valueSize, weight: emphasised ? .semibold : .regular)
                        .monospaced())
                    .foregroundStyle(emphasised ? Palette.primaryText : Palette.label(valueAlpha))
            }
            .padding(.vertical, ruled ? 8 : 0)
        }
    }
}


/// An image that fills its container without dragging the layout out with it.
///
/// `Image.resizable().scaledToFill()` reports the *filled* size as its own, so
/// a VStack around it sizes to that and the screen's gutters disappear off
/// both edges. `Color.clear` has no intrinsic size of its own, so it takes the
/// proposal and the overlay is clipped to it instead of the other way round.
struct PhotoFill: View {
    let image: UIImage
    var opacity: Double = 1

    var body: some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(opacity)
            }
            .clipped()
    }
}
