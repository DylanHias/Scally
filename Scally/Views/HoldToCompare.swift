import SwiftUI

/// Zoom shared between the comparison and the bar above it: the design puts
/// the `100%` badge in the top bar, not floating over the photo, so the two
/// have to agree on a number that only the comparison can compute.
@MainActor @Observable
final class CompareState {
    var percentLabel = "100%"
    @ObservationIgnored fileprivate var toggle: (() -> Void)?
    func toggleOneToOne() { toggle?() }
}

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
    let state: CompareState

    @State private var showingOriginal = false
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maximumZoom: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.photoWell

                Image(uiImage: showingOriginal ? before : after)
                    .resizable()
                    // Nearest-neighbour ONLY past 1:1, where it shows true
                    // pixels. Below that it is downsampling, and nearest
                    // downsampling aliases the image into a smudged mess.
                    .interpolation(isMagnifiedPastActualPixels(viewport: geometry.size)
                                   ? .none : .high)
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
                    Spacer()
                    Text(hint(viewport: geometry.size))
                        .font(Typography.caption)
                        .tracking(1.54)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(Color.black.opacity(0.5), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22)))
                        .animation(.snappy(duration: 0.12), value: showingOriginal)
                }
                .padding(.bottom, 16)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.08, maximumDistance: .infinity) {
            } onPressingChanged: { pressing in
                showingOriginal = pressing
            }
            .onAppear {
                state.toggle = { toggleOneToOne(viewport: geometry.size) }
                state.percentLabel = zoomLabel(viewport: geometry.size)
            }
            .onChange(of: zoom) { _, _ in
                state.percentLabel = zoomLabel(viewport: geometry.size)
            }
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 1), maximumZoom) }

    private func isMagnifiedPastActualPixels(viewport: CGSize) -> Bool {
        fitScale(viewport: viewport) * zoom * UIScreen.main.scale >= 1
    }

    /// Only suggest tapping 100% when the view is actually below actual pixels.
    /// A small output can already exceed 1:1 at fit, and telling someone to go
    /// find real pixels they are already looking at is nonsense.
    private func hint(viewport: CGSize) -> String {
        if showingOriginal { return "ORIGINAL" }
        let effective = fitScale(viewport: viewport) * zoom * UIScreen.main.scale
        return effective < 0.99 ? "TAP 100% FOR REAL PIXELS" : "HOLD TO SEE ORIGINAL"
    }

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

/// The `100%` pill in the top bar. Tapping it snaps to actual pixels.
struct ZoomBadge: View {
    let state: CompareState

    var body: some View {
        Button { state.toggleOneToOne() } label: {
            Text(state.percentLabel)
                .font(.system(size: 12.5, weight: .semibold).monospaced())
                .foregroundStyle(Palette.primaryText)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Palette.outline(0.24)))
        }
    }
}
