import SwiftUI

/// The launch mark, transcribed from the design's turn 4a.
///
/// Proportions are the design's, as fractions of the screen width (the source
/// sets `font-size:390px` on the mark and expresses everything in em against
/// it, so every number here scales with the phone):
///
///     mark box      0.44em      corner arm   26% of the box, plus one stroke
///     stroke        0.013em     outer radius 0.016em
///     pixel         34/390em    pixel radius 4/390em
///
/// It is the icon's drawing at the launch screen's proportions - four corner
/// rules, not four groups of squares. `tools/make_icon.py` bakes the same mark
/// for the home screen; change one and change the other.
enum MarkGeometry {
    static let box: CGFloat = 0.44
    static let armFraction: CGFloat = 0.26
    static let stroke: CGFloat = 0.013
    static let radius: CGFloat = 0.016
    static let pixel: CGFloat = 34.0 / 390.0
    static let pixelRadius: CGFloat = 4.0 / 390.0

    static let bracket = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let amber = Color(red: 226 / 255, green: 164 / 255, blue: 94 / 255)
}

/// Four corner rules. Each is the outer rounded box minus the inner one, which
/// is how a CSS `border-left` + `border-top` with a corner radius resolves:
/// round outside, all but square inside.
struct Brackets: Shape {
    let stroke: CGFloat
    let arm: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [rect.minX, rect.maxX] {
            for y in [rect.minY, rect.maxY] {
                let sx: CGFloat = x == rect.minX ? 1 : -1
                let sy: CGFloat = y == rect.minY ? 1 : -1
                let outer = CGRect(x: min(x, x + arm * sx), y: min(y, y + arm * sy),
                                   width: arm, height: arm)
                let inner = CGRect(x: min(x + stroke * sx, x + arm * sx),
                                   y: min(y + stroke * sy, y + arm * sy),
                                   width: arm - stroke, height: arm - stroke)
                path.addRoundedRect(in: outer,
                                    cornerSize: CGSize(width: radius, height: radius))
                path.addRoundedRect(in: inner,
                                    cornerSize: CGSize(width: max(0, radius - stroke),
                                                       height: max(0, radius - stroke)))
            }
        }
        return path
    }
}

/// The cold-start animation, on the design's own score.
///
/// Read off the source's keyframes against its 3.4 s cycle, which is the real
/// 2.2 s launch followed by an idle tail so the design loops:
///
///     0.20 s  brackets visible at 1.5x       0.71 s  brackets at rest
///     0.75 s  pixel landed                   1.19 s  hold ends
///     1.63 s  pixel gone at 4x               1.70 s  brackets gone at 9x
///     1.90 s  splash cleared                 2.24 s  app fully in
///
/// It is not a loading spinner: it plays once, and the hold - the only beat
/// that can be shortened without breaking the movement - ends the moment the
/// app is ready.
struct LaunchView: View {
    let readiness: AppReadiness
    /// Fires at 1.90 s, when the splash has cleared and the app should be
    /// coming up underneath. The design brings the app in under the clearing
    /// splash, after the mark has gone: Import is never behind the mark.
    let onSplashCleared: () -> Void
    let onFinish: () -> Void

    @State private var markScale: CGFloat = 1.5
    @State private var markOpacity: Double = 0
    @State private var pixelScale: CGFloat = 0.4
    @State private var pixelOpacity: Double = 0
    @State private var splashOpacity: Double = 1

    private enum Beat {
        static let appear = 0.204
        static let land = 0.714
        static let pixelLand = 0.748
        static let holdEnds = 1.190
        static let pixelGone = 1.632
        static let marksGone = 1.700
        static let splashClear = 1.904
    }

    /// cubic-bezier(.3,.8,.25,1) - the source's easing for both mark tracks.
    private func markCurve(_ duration: Double) -> Animation {
        .timingCurve(0.3, 0.8, 0.25, 1, duration: duration)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let box = MarkGeometry.box * width

            ZStack {
                Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
                    .ignoresSafeArea()
                    .opacity(splashOpacity)

                Brackets(stroke: MarkGeometry.stroke * width,
                         arm: MarkGeometry.armFraction * box + MarkGeometry.stroke * width,
                         radius: MarkGeometry.radius * width)
                    .fill(MarkGeometry.bracket, style: FillStyle(eoFill: true))
                    .frame(width: box, height: box)
                    .scaleEffect(markScale)
                    .opacity(markOpacity)

                RoundedRectangle(cornerRadius: MarkGeometry.pixelRadius * width)
                    .fill(MarkGeometry.amber)
                    .frame(width: MarkGeometry.pixel * width,
                           height: MarkGeometry.pixel * width)
                    .scaleEffect(pixelScale)
                    .opacity(pixelOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await play() }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func play() async {
        withAnimation(.easeOut(duration: Beat.appear)) { markOpacity = 1 }
        withAnimation(markCurve(Beat.land)) { markScale = 1 }
        withAnimation(markCurve(Beat.pixelLand - 0.408).delay(0.408)) {
            pixelScale = 1
            pixelOpacity = 1
        }
        try? await Task.sleep(for: .seconds(Beat.pixelLand))

        // The hold, and the only beat that may be cut short.
        let deadline = ContinuousClock.now.advanced(by: .seconds(Beat.holdEnds - Beat.pixelLand))
        while ContinuousClock.now < deadline, !readiness.isReady {
            try? await Task.sleep(for: .milliseconds(20))
        }

        withAnimation(markCurve(Beat.pixelGone - Beat.holdEnds)) {
            pixelScale = 4
            pixelOpacity = 0
        }
        withAnimation(markCurve(Beat.marksGone - Beat.holdEnds)) {
            markScale = 9
            markOpacity = 0
        }
        try? await Task.sleep(for: .seconds(Beat.marksGone - Beat.holdEnds))

        onSplashCleared()
        withAnimation(.easeOut(duration: Beat.splashClear - Beat.marksGone)) {
            splashOpacity = 0
        }
        try? await Task.sleep(for: .seconds(Beat.splashClear - Beat.marksGone))
        onFinish()
    }
}
