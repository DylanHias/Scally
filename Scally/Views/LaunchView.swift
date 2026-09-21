import SwiftUI

/// The mark's geometry, transcribed from `tools/make_icon.py`.
///
/// The icon and this animation are the same drawing at different sizes, so the
/// thing that lands on the home screen is the thing that opens. Change one set
/// of these numbers and change the other, or the mark stops matching itself.
enum Mark {
    static let inset: CGFloat = 0.176       // outer edge of the corner brackets
    static let block: CGFloat = 0.107       // side of one square
    static let gap: CGFloat = 0.025         // space between squares of one bracket
    static let pixelSide: CGFloat = 0.127   // the single amber square
    static let radius: CGFloat = 0.010

    static let bracket = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let pixel = Color(red: 226 / 255, green: 164 / 255, blue: 94 / 255)
}

/// Four corner brackets, each an L of three squares, drawn at `spread`.
///
/// `spread` is 1 at rest. Above 1 the brackets move out from the centre, and
/// they are deliberately allowed to leave the shape's own frame - that is how
/// the exit beat gets them past the screen edge.
struct Brackets: Shape {
    var spread: CGFloat

    var animatableData: CGFloat {
        get { spread }
        set { spread = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let block = Mark.block * size
        let arm = block + Mark.gap * size
        let radius = Mark.radius * size
        let centre = size / 2
        let offset = (Mark.inset * size - centre) * spread + centre

        var path = Path()
        for horizontal in [true, false] {
            for vertical in [true, false] {
                let originX = horizontal ? rect.minX + offset : rect.maxX - offset - block
                let originY = vertical ? rect.minY + offset : rect.maxY - offset - block
                for (dx, dy) in [(0.0, 0.0), (arm, 0.0), (0.0, arm)] {
                    let x = originX + (horizontal ? dx : -dx)
                    let y = originY + (vertical ? dy : -dy)
                    path.addRoundedRect(
                        in: CGRect(x: x, y: y, width: block, height: block),
                        cornerSize: CGSize(width: radius, height: radius)
                    )
                }
            }
        }
        return path
    }
}

/// The cold-start animation from the design's §5.
///
/// It is not a loading spinner. It plays once, on a fixed score, and the moment
/// the app is ready it cuts the hold short rather than running out the clock.
/// The landing and the exit always play in full: a mark chopped off mid-flight
/// reads as a crash, not as a launch.
struct LaunchView: View {
    let readiness: AppReadiness
    let onFinish: () -> Void

    @State private var spread: CGFloat = Score.open
    @State private var pixelScale: CGFloat = 0.25
    @State private var pixelOpacity: Double = 0

    /// The beats, verbatim from the design: 0.00 s black with the brackets 50%
    /// open; 0.70 s they close to resting size and the amber pixel lands;
    /// 1.20 s hold; 1.70 s they keep opening, past the screen edge; 2.20 s end.
    private enum Score {
        static let open: CGFloat = 1.5
        static let close: Double = 0.70
        static let hold: Double = 1.00
        static let exit: Double = 0.50
    }

    var body: some View {
        GeometryReader { geometry in
            let side = markSide(in: geometry.size)

            ZStack {
                Color.black.ignoresSafeArea()

                ZStack {
                    Brackets(spread: spread)
                        .fill(Mark.bracket)

                    RoundedRectangle(cornerRadius: Mark.radius * side)
                        .fill(Mark.pixel)
                        .frame(width: Mark.pixelSide * side, height: Mark.pixelSide * side)
                        .scaleEffect(pixelScale)
                        .opacity(pixelOpacity)
                }
                .frame(width: side, height: side)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await play(exitingTo: exitSpread(in: geometry.size)) }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func play(exitingTo exit: CGFloat) async {
        withAnimation(.easeOut(duration: Score.close)) { spread = 1 }
        withAnimation(.spring(duration: 0.32, bounce: 0.3).delay(Score.close - 0.22)) {
            pixelScale = 1
            pixelOpacity = 1
        }
        try? await Task.sleep(for: .seconds(Score.close))

        // The hold is the only part that may be cut short, and it is cut the
        // instant the app is ready rather than at some polled interval.
        let deadline = ContinuousClock.now.advanced(by: .seconds(Score.hold))
        while ContinuousClock.now < deadline, !readiness.isReady {
            try? await Task.sleep(for: .milliseconds(20))
        }

        withAnimation(.easeIn(duration: Score.exit)) {
            spread = exit
            pixelOpacity = 0
        }
        try? await Task.sleep(for: .seconds(Score.exit))
        onFinish()
    }

    private func markSide(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.52
    }

    /// The `spread` at which the brackets have cleared the longer screen edge.
    ///
    /// Solved rather than guessed: a constant that clears a 6.9" phone leaves
    /// brackets parked on the edge of a smaller one.
    private func exitSpread(in size: CGSize) -> CGFloat {
        let side = markSide(in: size)
        let centre = side / 2
        let rest = Mark.inset * side
        let block = Mark.block * side
        let margin = max(size.width, size.height) / 2 - centre
        guard centre > rest else { return 8 }
        return (centre + block + margin) / (centre - rest) * 1.08
    }
}
