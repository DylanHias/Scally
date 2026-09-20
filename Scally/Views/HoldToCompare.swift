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
                        Button(action: toggleOneToOne) {
                            Text(zoomLabel(viewport: geometry.size))
                                .font(Typography.badge)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    Spacer()
                    Text(showingOriginal ? "ORIGINAL" : "HOLD TO SEE ORIGINAL")
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

    /// Percentage of true 1:1, where one image pixel covers one device pixel.
    private func zoomLabel(viewport: CGSize) -> String {
        let fit = min(viewport.width / after.size.width, viewport.height / after.size.height)
        let effective = fit * zoom * UIScreen.main.scale
        return "\(Int((effective * 100).rounded()))%"
    }

    private func toggleOneToOne() {
        withAnimation(.snappy) {
            if committedZoom > 1.01 {
                zoom = 1; committedZoom = 1
                offset = .zero; committedOffset = .zero
            } else {
                zoom = maximumZoom / 3
                committedZoom = zoom
            }
        }
    }
}
