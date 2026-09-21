import SwiftUI

/// Configure, transcribed from the design's screen 3 and its S3 edge case.
///
/// It sits inline on the photo rather than in a sheet: the numbers are stated
/// plainly while there is still a decision to make.
struct ConfigureView: View {
    let pending: PendingImage

    @State private var scale: Int
    @Environment(\.dismiss) private var dismiss

    /// Built once, not on every access.
    ///
    /// This was a computed property, so each read constructed a fresh model and
    /// re-measured free memory. Two reads in one render could disagree, and did:
    /// the screen showed "4x would need 744 MB, more than this iPhone can give"
    /// directly above a button that still said "Upscale" rather than
    /// "Upscale 2x", because the notice and the button had asked different
    /// models.
    private let model: ConfigureModel

    init(pending: PendingImage) {
        self.pending = pending
        let model = ConfigureModel(inputWidth: pending.width, inputHeight: pending.height,
                                   inputBytes: pending.byteCount)
        self.model = model
        _scale = State(initialValue: model.defaultScale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenBar(leading: "Back", title: pending.filename) { dismiss() }
                    trailing: { Color.clear.frame(width: 40, height: 1) }
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                photo
                controls
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var photo: some View {
        PhotoFill(image: pending.preview)
            .background(Palette.photoWell)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, Metrics.gutter)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ScalePicker(scale: $scale, model: model)

            if let reason = model.unavailableReason(scale: 4) {
                ClampNotice(text: reason).padding(.top, 14)
            }

            VStack(spacing: 0) {
                DetailRow(label: "INPUT",
                          value: "\(pending.width) × \(pending.height) px · \(formatted(pending.byteCount))",
                          ruled: true)
                DetailRow(label: "OUTPUT",
                          value: "\(model.outputDimensions(scale: scale).width) × \(model.outputDimensions(scale: scale).height) px · ~\(formatted(model.estimatedBytes(scale: scale)))",
                          emphasised: true, ruled: true)
                DetailRow(label: "ESTIMATE",
                          value: "\(model.estimatedSeconds(scale: scale)) s · on device",
                          ruled: true)
            }
            .padding(.top, 16)

            NavigationLink {
                ProcessingView(pending: pending, scale: scale)
            } label: {
                FilledButtonLabel(title: model.availableScales.count == 1
                                  ? "Upscale \(scale)×" : "Upscale")
            }
            .disabled(!model.canUpscaleAtAll)
            .padding(.top, 18)

            Text("Detail is reconstructed, not invented. Faces stay as they are.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.label(0.34))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 18)
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// The 2x / 4x track. An unavailable scale stays visible and dimmed rather
/// than disappearing: the design's S3 explains why it cannot be had, which
/// only works if the thing it refers to is still on screen.
struct ScalePicker: View {
    @Binding var scale: Int
    let model: ConfigureModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ConfigureModel.offeredScales, id: \.self) { candidate in
                let available = model.isAvailable(scale: candidate)
                let selected = scale == candidate
                Button { scale = candidate } label: {
                    Text("\(candidate)×")
                        .font(.system(size: 15, weight: selected ? .semibold : .medium)
                            .monospaced())
                        .foregroundStyle(foreground(selected: selected, available: available))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Palette.segmentSelected)
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                            }
                        }
                }
                // .plain is required: the default button style repaints the
                // label with its own tint, which made the selected segment's
                // text vanish against its own fill.
                .buttonStyle(.plain)
                .disabled(!available)
            }
        }
        .padding(3)
        .background(Palette.segmentTrack, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.hairline))
    }

    private func foreground(selected: Bool, available: Bool) -> Color {
        guard available else { return Palette.disabledSegment }
        return selected ? Palette.primaryText : Palette.label(0.56)
    }
}

/// S3: the memory clamp, stated in the units the user's phone actually deals
/// in, with the amber ring the design uses for a notice that is not an error.
struct ClampNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .strokeBorder(Palette.accent, lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(Palette.noticeText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .background(Palette.noticeSurface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.outline(0.1)))
    }
}
