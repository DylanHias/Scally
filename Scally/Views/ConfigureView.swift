import SwiftUI

/// Configure sits inline on the photo rather than in a sheet: the numbers are
/// stated plainly while there is still a decision to make.
struct ConfigureView: View {
    let pending: PendingImage

    @State private var scale: Int
    @Environment(\.dismiss) private var dismiss

    private var model: ConfigureModel {
        ConfigureModel(inputWidth: pending.width, inputHeight: pending.height,
                       inputBytes: pending.byteCount)
    }

    init(pending: PendingImage) {
        self.pending = pending
        let initial = ConfigureModel(inputWidth: pending.width, inputHeight: pending.height)
        _scale = State(initialValue: initial.defaultScale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                photo
                Spacer(minLength: 12)
                metrics
                footer
            }
        }
        .navigationTitle(pending.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
    }

    private var photo: some View {
        Image(uiImage: pending.preview)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.card))
            .overlay(alignment: .bottom) { scaleSelector.padding(14) }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
    }

    private var scaleSelector: some View {
        HStack(spacing: 4) {
            ForEach(ConfigureModel.offeredScales, id: \.self) { candidate in
                let available = model.isAvailable(scale: candidate)
                Button { scale = candidate } label: {
                    Text("\(candidate)×")
                        .font(Typography.metric)
                        .foregroundStyle(foreground(for: candidate, available: available))
                        .frame(width: 58, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(scale == candidate ? Palette.primaryText : .clear)
                        )
                }
                // .plain is required: the default button style repaints the
                // label with its own tint, which made the selected segment's
                // text vanish against its own fill.
                .buttonStyle(.plain)
                .disabled(!available)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
    }

    private func foreground(for candidate: Int, available: Bool) -> Color {
        guard available else { return Palette.tertiaryText }
        return scale == candidate ? Palette.background : Palette.primaryText
    }

    private var metrics: some View {
        VStack(spacing: 12) {
            if let reason = model.unavailableReason(scale: 4) {
                Text(reason)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.control))
            }

            MetricRow(label: "INPUT",
                      value: "\(pending.width) × \(pending.height) px · \(formatted(pending.byteCount))")
            MetricRow(label: "OUTPUT",
                      value: "\(model.outputDimensions(scale: scale).width) × \(model.outputDimensions(scale: scale).height) px · ~\(formatted(model.estimatedBytes(scale: scale)))")
            MetricRow(label: "ESTIMATE",
                      value: "\(model.estimatedSeconds(scale: scale)) s · on device")
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            NavigationLink {
                ProcessingView(pending: pending, scale: scale)
            } label: {
                Text(model.availableScales.count == 1 ? "Upscale \(scale)×" : "Upscale")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Palette.background)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.primaryText, in: RoundedRectangle(cornerRadius: Metrics.control))
            }
            .disabled(!model.canUpscaleAtAll)

            Text("Detail is reconstructed, not invented. Faces stay as they are.")
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Shown when the photo library is off limits. States what the app can and
/// cannot see, rather than apologising.
struct LibraryDeniedView: View {
    let onChooseSpecific: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("No access to your library")
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.primaryText)

            Text("Scally can only see photos you give it. Nothing is read in the background and nothing is uploaded either way.")
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(Typography.body.weight(.semibold))
            .foregroundStyle(Palette.background)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.primaryText, in: RoundedRectangle(cornerRadius: Metrics.control))

            Button("Choose specific photos", action: onChooseSpecific)
                .font(Typography.body)
                .foregroundStyle(Palette.primaryText)

            FieldLabel("SETTINGS → PRIVACY → PHOTOS → SCALLY")
            Spacer()

            VStack(spacing: 3) {
                Text("Runs entirely on this iPhone.")
                Text("Nothing is uploaded. No account. No internet.")
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.tertiaryText)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Metrics.gutter)
    }
}
