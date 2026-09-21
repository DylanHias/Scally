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
    @AppStorage("sharpen") private var sharpen = 0.45
    @State private var note: String?

    struct Outcome: Identifiable {
        let id: String
        let title: String
        let parameters: String
        let seconds: Double
        let image: UIImage?
        let failure: String?
    }

    /// A centre crop of the photo at its own resolution, capped so a
    /// four-model sweep stays quick.
    ///
    /// An earlier version shrank the photo to 180px and re-encoded it at JPEG
    /// quality 40 first. That destroyed the input so thoroughly that every
    /// model produced smudge, and the comparison said nothing about any of
    /// them. Judge the models on real pixels.
    private let cropEdge = 900

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
                // A 1:1 centre crop. Fitting the whole 3600px result into a
                // ~350pt card downsamples it ~3.4x, which destroys exactly the
                // differences this screen exists to show.
                GeometryReader { geometry in
                    let side = geometry.size.width
                    Image(uiImage: Self.centreCropForDisplay(image, side: side))
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.control))
                }
                .aspectRatio(1, contentMode: .fit)
                Text("shown at 1:1 · full result is \(Int(image.size.width))px")
                    .font(Typography.caption).foregroundStyle(Palette.tertiaryText)
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

        guard let small = Self.centreCrop(pending.preview, edge: cropEdge) else {
            note = "Couldn't prepare the image."; return
        }
        let source = FileManager.default.temporaryDirectory
            .appending(path: "compare-\(UUID().uuidString).png")
        try? small.data.write(to: source)
        // Also drop the input into Documents so the real output can be pulled
        // off the device and inspected, rather than judged through a screen.
        try? small.data.write(to: Self.dumpDirectory().appending(path: "00-input.png"))
        note = "Input: a \(Int(small.size.width))×\(Int(small.size.height)) centre crop of your photo, unmodified. Each model upscales it 4×."

        results.append(Outcome(id: "input", title: "Input (bicubic 4×)", parameters: "—",
                               seconds: 0, image: Self.bicubic(small.image, scale: 4), failure: nil))

        for option in UpscalerOption.all {
            running = option.title
            let started = Date()
            do {
                let pipeline = UpscalePipeline(upscaler: try option.makeUpscaler(),
                                               faceRestorer: NoopFaceRestorer(),
                                               sharpener: .forUpscale(intensity: sharpen, scale: 4))
                let result = try await pipeline.run(source: source, requestedScale: 4) { _ in }
                let elapsed = Date().timeIntervalSince(started)
                results.append(Outcome(id: option.id, title: option.title,
                                       parameters: option.parameters, seconds: elapsed,
                                       image: UIImage(contentsOfFile: result.outputURL.path),
                                       failure: nil))
                let dumped = Self.dumpDirectory()
                    .appending(path: "\(option.id).\(result.outputURL.pathExtension)")
                try? FileManager.default.removeItem(at: dumped)
                try? FileManager.default.copyItem(at: result.outputURL, to: dumped)
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

    /// Crops the centre at native resolution so one point maps to one device
    /// pixel - the only way differences between these models are visible.
    static func centreCropForDisplay(_ image: UIImage, side: CGFloat) -> UIImage {
        let pixels = side * UIScreen.main.scale
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let take = min(pixels, width, height)
        let origin = CGPoint(x: ((width - take) / 2).rounded(),
                             y: ((height - take) / 2).rounded())
        guard let cg = image.cgImage?.cropping(
            to: CGRect(origin: origin, size: CGSize(width: take, height: take))
        ) else { return image }
        return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
    }

    /// Documents/compare - readable over devicectl for off-device inspection.
    static func dumpDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appending(path: "compare")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A centre crop at the photo's own resolution - no resampling, no
    /// re-encoding. Whatever degradation the photo already carries is the
    /// degradation the models get to work on.
    private static func centreCrop(_ image: UIImage, edge: Int)
        -> (data: Data, image: UIImage, size: CGSize)? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let side = min(CGFloat(edge), pixelWidth, pixelHeight)
        let origin = CGPoint(x: ((pixelWidth - side) / 2).rounded(),
                             y: ((pixelHeight - side) / 2).rounded())
        guard let cg = image.cgImage?.cropping(
            to: CGRect(origin: origin, size: CGSize(width: side, height: side))
        ) else { return nil }
        let cropped = UIImage(cgImage: cg)
        guard let data = cropped.pngData(), let reloaded = UIImage(data: data) else { return nil }
        return (data, reloaded, CGSize(width: side, height: side))
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
