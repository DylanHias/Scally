import SwiftUI

/// Press and hold reveals the original. Chosen over a draggable divider: one
/// gesture, no conflict with panning, and the whole frame changes at once so
/// the difference is unmissable.
///
/// Pinch-zoom is not decoration here. Fitted to a phone screen a 4x upscale is
/// indistinguishable from its input, so without a real 1:1 view the app appears
/// to do nothing at all.
struct HoldToCompare: View {
    let before: UIImage
    let after: UIImage

    @State private var showingOriginal = false
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maximumZoom: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                Image(uiImage: showingOriginal ? before : after)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .offset(offset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .gesture(
                        SimultaneousGesture(
                            MagnifyGesture()
                                .onChanged { zoom = clamp(committedZoom * $0.magnification) }
                                .onEnded { _ in committedZoom = zoom },
                            DragGesture()
                                .onChanged {
                                    offset = CGSize(width: committedOffset.width + $0.translation.width,
                                                    height: committedOffset.height + $0.translation.height)
                                }
                                .onEnded { _ in committedOffset = offset }
                        )
                    )

                VStack {
                    HStack {
                        Spacer()
                        Button { toggleOneToOne(viewport: geometry.size) } label: {
                            Text(zoomLabel(viewport: geometry.size))
                                .font(Typography.badge)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    Spacer()
                    Text(hint(viewport: geometry.size))
                        .font(Typography.sectionLabel)
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(showingOriginal ? 0.95 : 0.6))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .animation(.snappy(duration: 0.12), value: showingOriginal)
                }
                .padding(14)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.08, maximumDistance: .infinity) {
            } onPressingChanged: { pressing in
                showingOriginal = pressing
            }

        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 1), maximumZoom) }

    /// Only suggest tapping 100% when the view is actually below actual pixels.
    /// A small output can already exceed 1:1 at fit, and telling someone to go
    /// find real pixels they are already looking at is nonsense.
    private func hint(viewport: CGSize) -> String {
        if showingOriginal { return "ORIGINAL" }
        let effective = fitScale(viewport: viewport) * zoom * UIScreen.main.scale
        return effective < 0.99 ? "TAP 100% FOR REAL PIXELS" : "HOLD TO SEE ORIGINAL"
    }

    /// Fit-to-frame scale for the output image, in points per image point.
    private func fitScale(viewport: CGSize) -> CGFloat {
        guard after.size.width > 0, after.size.height > 0 else { return 1 }
        return min(viewport.width / after.size.width, viewport.height / after.size.height)
    }

    /// The `zoom` multiplier at which one output pixel covers one device pixel.
    ///
    /// This is the whole point of the screen. Fitted to the frame, a 4x upscale
    /// is arithmetically indistinguishable from its input - both carry more
    /// pixels than the display area, so both resolve sharp and holding to
    /// compare shows nothing. The difference only exists at actual pixels.
    private func oneToOneZoom(viewport: CGSize) -> CGFloat {
        let fit = fitScale(viewport: viewport)
        guard fit > 0 else { return 1 }
        return 1 / (fit * UIScreen.main.scale)
    }

    /// Percentage of true 1:1, where one image pixel covers one device pixel.
    private func zoomLabel(viewport: CGSize) -> String {
        let effective = fitScale(viewport: viewport) * zoom * UIScreen.main.scale
        return "\(Int((effective * 100).rounded()))%"
    }

    private func toggleOneToOne(viewport: CGSize) {
        withAnimation(.snappy) {
            let target = clamp(oneToOneZoom(viewport: viewport))
            if abs(committedZoom - target) < 0.05 {
                zoom = 1
            } else {
                zoom = target
            }
            committedZoom = zoom
            offset = .zero
            committedOffset = .zero
        }
    }

}
