import SwiftUI
import ScallyKit

/// Processing, transcribed from the design's screen 4.
///
/// The photo stays on screen at half opacity behind a scrim, so the thing
/// being worked on is still the thing you are looking at, and the percentage
/// is read against it rather than against an empty panel.
struct ProcessingView: View {
    let pending: PendingImage
    let scale: Int

    @AppStorage("sharpen") private var sharpen = 0.45
    @State private var model = ProcessingModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("UPSCALING · \(scale)×")
                        .font(.system(size: 11.5).monospaced())
                        .tracking(Tracking.subtitle)
                        .foregroundStyle(Palette.label(0.5))
                    Spacer()
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 10)

                panel
                readouts
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            model.start(source: pending.url, scale: scale, sharpen: sharpen)
        }
        .navigationDestination(item: finished) { result in
            ResultView(pending: pending, result: result)
        }
    }

    private var panel: some View {
        ZStack {
            Image(uiImage: pending.preview)
                .resizable().scaledToFill()
                .opacity(0.5)
            Color.black.opacity(0.42)

            Text("\(Int(model.progress * 100))%")
                .font(.system(size: 56, weight: .light).monospaced())
                .tracking(-1.68)
                .foregroundStyle(Palette.primaryText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.photoWell)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
    }

    private var readouts: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.outline(0.14))
                    Capsule().fill(Palette.accent)
                        .frame(width: geometry.size.width * max(0, min(1, model.progress)))
                }
            }
            .frame(height: 2)

            HStack {
                readout(String(format: "ELAPSED %.1f s", model.elapsed), alpha: 0.5)
                Spacer()
                if let remaining = model.estimatedRemaining {
                    readout(String(format: "REMAINING ~%.1f s", remaining), alpha: 0.5)
                }
            }
            .padding(.top, 12)

            HStack {
                readout("OUTPUT", alpha: 0.34)
                Spacer()
                readout("\(pending.width * scale) × \(pending.height * scale) px", alpha: 0.34)
            }
            .padding(.top, 6)

            Button {
                model.cancel()
                dismiss()
            } label: {
                OutlineButtonLabel(title: "Cancel")
            }
            .padding(.top, 22)

            Text("Screen stays awake until it finishes")
                .font(.system(size: 12))
                .foregroundStyle(Palette.label(0.34))
                .padding(.top, 12)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 20)
    }

    /// The design writes these as one run of monospaced text - `ELAPSED 3.4 s`
    /// - not as a caption above a value. The unit is lower case.
    private func readout(_ text: String, alpha: Double) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.label(alpha))
            .contentTransition(.numericText())
    }

    private var finished: Binding<UpscaleResult?> {
        Binding(
            get: { if case .finished(let result) = model.state { result } else { nil } },
            set: { _ in }
        )
    }
}
