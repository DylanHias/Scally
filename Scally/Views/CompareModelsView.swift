import SwiftUI
import PhotosUI
import ScallyKit

/// Runs every bundled model over the same photo so quality and speed can be
/// judged side by side on real hardware, rather than argued about.
struct CompareModelsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var pending: PendingImage?
    @State private var results: [Outcome] = []
    @State private var running: String?
    @State private var note: String?

    struct Outcome: Identifiable {
        let id: String
        let title: String
        let parameters: String
        let seconds: Double
        let image: UIImage?
        let failure: String?
    }

    /// Source is downscaled to this before running: a small, degraded input is
    /// the case these models exist for, and it keeps a four-model sweep quick.
    private let workingEdge = 180

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        picker
                        if let note {
                            Text(note).font(Typography.caption).foregroundStyle(Palette.secondaryText)
                        }
                        if let running {
                            HStack(spacing: 8) {
                                ProgressView().tint(Palette.accent)
                                Text("running \(running)…").font(Typography.caption)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                        ForEach(results) { outcome in card(outcome) }
                    }
                    .padding(Metrics.gutter)
                }
            }
            .navigationTitle("Compare models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task {
                    pending = await PendingImage.load(from: item)
                    selection = nil
                    await runAll()
                }
            }
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Text(pending == nil ? "Choose a photo to compare" : "Choose another photo")
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Palette.background)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Palette.primaryText, in: RoundedRectangle(cornerRadius: Metrics.control))
        }
        .disabled(running != nil)
    }

    private func card(_ outcome: Outcome) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(outcome.title).font(Typography.body.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(outcome.parameters).font(Typography.caption.monospaced())
                    .foregroundStyle(Palette.tertiaryText)
                Spacer()
                Text(String(format: "%.1f s", outcome.seconds))
                    .font(Typography.metric).foregroundStyle(Palette.accent)
            }
            if let failure = outcome.failure {
                Text(failure).font(Typography.caption).foregroundStyle(Palette.destructive)
            } else if let image = outcome.image {
                Image(uiImage: image)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.control))
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.card))
        .overlay(RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.border))
    }

    private func runAll() async {
        guard let pending else { return }
        results = []
        note = nil

        // Downscale and re-encode as a low-quality JPEG: the point is to give
        // every model the same realistically damaged input.
        guard let small = Self.degrade(pending.preview, edge: workingEdge) else {
            note = "Couldn't prepare the image."; return
        }
        let source = FileManager.default.temporaryDirectory
            .appending(path: "compare-\(UUID().uuidString).jpg")
        try? small.data.write(to: source)
        note = "Input: \(Int(small.size.width))×\(Int(small.size.height)), JPEG quality 40. Each model upscales it 4×."

        results.append(Outcome(id: "input", title: "Input (bicubic 4×)", parameters: "—",
                               seconds: 0, image: Self.bicubic(small.image, scale: 4), failure: nil))

        for option in UpscalerOption.all {
            running = option.title
            let started = Date()
            do {
                let pipeline = UpscalePipeline(upscaler: try option.makeUpscaler(),
                                               faceRestorer: NoopFaceRestorer())
                let result = try await pipeline.run(source: source, requestedScale: 4) { _ in }
                let elapsed = Date().timeIntervalSince(started)
                results.append(Outcome(id: option.id, title: option.title,
                                       parameters: option.parameters, seconds: elapsed,
                                       image: UIImage(contentsOfFile: result.outputURL.path),
                                       failure: nil))
                try? FileManager.default.removeItem(at: result.outputURL)
            } catch {
                results.append(Outcome(id: option.id, title: option.title,
                                       parameters: option.parameters,
                                       seconds: Date().timeIntervalSince(started),
                                       image: nil, failure: error.localizedDescription))
            }
        }
        running = nil
        try? FileManager.default.removeItem(at: source)
    }

    private static func degrade(_ image: UIImage, edge: Int)
        -> (data: Data, image: UIImage, size: CGSize)? {
        let longest = max(image.size.width, image.size.height)
        let ratio = CGFloat(edge) / longest
        let size = CGSize(width: (image.size.width * ratio).rounded(),
                          height: (image.size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = small.jpegData(compressionQuality: 0.4),
              let reloaded = UIImage(data: data) else { return nil }
        return (data, reloaded, size)
    }

    private static func bicubic(_ image: UIImage, scale: Int) -> UIImage {
        let size = CGSize(width: image.size.width * CGFloat(scale),
                          height: image.size.height * CGFloat(scale))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
