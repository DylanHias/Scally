import SwiftUI
import ScallyKit

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
                Image(uiImage: pending.preview)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.card))
                    .opacity(0.4)
                    .overlay(alignment: .center) { readout }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 8)

                Spacer(minLength: 12)
                metrics

                Button("Cancel") {
                    model.cancel()
                    dismiss()
                }
                .font(Typography.body)
                .foregroundStyle(Palette.primaryText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.control))
                .overlay(RoundedRectangle(cornerRadius: Metrics.control).strokeBorder(Palette.border))
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 18)

                Text("Screen stays awake until it finishes")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
        }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            model.start(source: pending.url, scale: scale, sharpen: sharpen)
        }
        .navigationDestination(item: finished) { result in
            ResultView(pending: pending, result: result)
        }
    }

    private var readout: some View {
        VStack(spacing: 10) {
            FieldLabel("UPSCALING · \(scale)×")
            Text("\(Int(model.progress * 100))%")
                .font(Typography.metricLarge)
                .foregroundStyle(Palette.primaryText)
                .contentTransition(.numericText())
            ProgressView(value: model.progress)
                .tint(Palette.accent)
                .frame(width: 160)
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Metrics.sheet))
    }

    private var metrics: some View {
        VStack(spacing: 12) {
            // Two readouts, each a caption over a monospaced value, as the
            // design draws them. They were one run of uppercase caption text,
            // which lost the type distinction the rest of the app keeps
            // between a field's name and its number - and uppercased the unit
            // into `3.4 S`, where the design writes `3.4 s`.
            HStack(alignment: .top) {
                readout(label: "ELAPSED", value: String(format: "%.1f s", model.elapsed))
                Spacer()
                if let remaining = model.estimatedRemaining {
                    readout(label: "REMAINING",
                            value: String(format: "~%.1f s", remaining),
                            alignment: .trailing)
                }
            }
            MetricRow(label: "OUTPUT",
                      value: "\(pending.width * scale) × \(pending.height * scale) px")
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func readout(label: String, value: String,
                         alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            FieldLabel(label)
            Text(value)
                .font(Typography.metric)
                .foregroundStyle(Palette.primaryText)
                .contentTransition(.numericText())
        }
    }

    private var finished: Binding<UpscaleResult?> {
        Binding(
            get: { if case .finished(let result) = model.state { result } else { nil } },
            set: { _ in }
        )
    }
}
