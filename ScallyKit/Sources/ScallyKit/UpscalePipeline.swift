import Foundation
import Accelerate

public struct UpscaleResult: Sendable, Identifiable, Hashable {
    /// `navigationDestination(item:)` needs Identifiable and Hashable; observable
    /// state that wraps this needs Equatable, which Hashable implies.
    public var id: URL { outputURL }

    public let outputURL: URL
    public let outputWidth: Int
    public let outputHeight: Int
    public let appliedScale: Int
    public let requestedScale: Int
    public let duration: TimeInterval

    /// A public struct with an internal memberwise init cannot be constructed
    /// by consumers at all, which makes it useless for previews, fixtures and
    /// anything outside the package.
    public init(outputURL: URL, outputWidth: Int, outputHeight: Int,
                appliedScale: Int, requestedScale: Int, duration: TimeInterval) {
        self.outputURL = outputURL
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.appliedScale = appliedScale
        self.requestedScale = requestedScale
        self.duration = duration
    }

    public var wasClamped: Bool { appliedScale != requestedScale }
}

/// The only public entry point into ScallyKit.
public struct UpscalePipeline: Sendable {
    private let upscaler: any Upscaler
    private let faceRestorer: any FaceRestorer
    private let faceDetector: any FaceDetecting
    private let budget: MemoryBudget
    private let sharpener: Sharpener
    private let scratchDirectory: URL
    private let overlap = 16

    /// - Parameter scratchDirectory: where the memory-mapped working buffers
    ///   live. Per spec section 5 the app passes its Caches directory; these
    ///   files are deleted as soon as encoding finishes and are never the
    ///   final output. Injectable so tests can assert cleanup against a
    ///   directory nothing else writes to.
    public init(upscaler: any Upscaler,
                faceRestorer: any FaceRestorer = NoopFaceRestorer(),
                faceDetector: any FaceDetecting = NoFaceDetector(),
                budget: MemoryBudget = .current(),
                sharpener: Sharpener = .standard,
                scratchDirectory: URL = FileManager.default.temporaryDirectory) {
        self.upscaler = upscaler
        self.faceRestorer = faceRestorer
        self.faceDetector = faceDetector
        self.budget = budget
        self.sharpener = sharpener
        self.scratchDirectory = scratchDirectory
    }

    public func run(source: URL,
                    requestedScale: Int,
                    destinationDirectory: URL? = nil,
                    progress: @Sendable (Double) -> Void) async throws -> UpscaleResult {
        let started = Date()
        try Task.checkCancellation()

        let input = try ImageLoader.load(url: source)

        // Detected on the input, not the enlargement: the rectangles are
        // normalised, so they describe every later buffer just as well, at a
        // sixteenth of the work.
        let faces = input.makeCGImage().map(faceDetector.regions(in:)) ?? .none

        let decision = budget.resolveScale(requested: requestedScale,
                                           inputWidth: input.width,
                                           inputHeight: input.height)
        guard let effectiveScale = decision.scale else {
            throw UpscaleError.imageTooLarge(pixels: input.width * input.height)
        }

        // The model is 4x only; 2x is the 4x result downsampled.
        let modelScale = upscaler.scale
        let intermediateWidth = input.width * modelScale
        let intermediateHeight = input.height * modelScale

        let buffer = try MappedPixelBuffer(width: intermediateWidth,
                                           height: intermediateHeight,
                                           directory: scratchDirectory)
        let composer = TileComposer(buffer: buffer, overlap: overlap * modelScale)
        let grid = TileGrid(imageWidth: input.width, imageHeight: input.height,
                            tileSize: upscaler.inputTileSize, overlap: overlap)

        for (index, tile) in grid.tiles.enumerated() {
            try Task.checkCancellation()

            try autoreleasepool {
                var tilePixels = [UInt8](repeating: 0, count: tile.width * tile.height * 4)
                for row in 0..<tile.height {
                    let from = ((tile.y + row) * input.bytesPerRow) + tile.x * 4
                    let to = row * tile.width * 4
                    for byte in 0..<(tile.width * 4) {
                        tilePixels[to + byte] = input.pixels[from + byte]
                    }
                }

                let upscaled = try tilePixels.withUnsafeBytes { raw in
                    try upscaler.upscale(tile: raw.baseAddress!, width: tile.width,
                                         height: tile.height, bytesPerRow: tile.width * 4)
                }

                upscaled.pixels.withUnsafeBytes { raw in
                    composer.write(tile: tile.scaled(by: modelScale),
                                   pixels: raw.baseAddress!, bytesPerRow: upscaled.bytesPerRow)
                }
            }

            progress(Double(index + 1) / Double(grid.tiles.count))
        }

        try Task.checkCancellation()

        // v1's restorer is a no-op; the call site exists so adding one later is
        // a single-line change (spec section 2).
        _ = try faceRestorer.restore(image: buffer.baseAddress,
                                     width: intermediateWidth,
                                     height: intermediateHeight,
                                     bytesPerRow: buffer.bytesPerRow)

        if input.hasAlpha {
            let alpha = AlphaChannel.extract(from: input.pixels, width: input.width,
                                             height: input.height, bytesPerRow: input.bytesPerRow)
            let scaledAlpha = AlphaChannel.scaled(
                alpha,
                from: (input.width, input.height),
                to: (intermediateWidth, intermediateHeight)
            )
            let destination = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
            for y in 0..<intermediateHeight {
                let rowStart = y * buffer.bytesPerRow
                for x in 0..<intermediateWidth {
                    destination[rowStart + x * 4 + 3] = scaledAlpha[y * intermediateWidth + x]
                }
            }
        }

        let finalBuffer: MappedPixelBuffer
        if effectiveScale == modelScale {
            finalBuffer = buffer
        } else {
            finalBuffer = try Self.downsample(
                buffer,
                to: (input.width * effectiveScale, input.height * effectiveScale),
                directory: scratchDirectory
            )
        }

        let format = OutputWriter.Format.preferred(hasAlpha: input.hasAlpha)
        let directory = destinationDirectory ?? FileManager.default.temporaryDirectory
        let outputURL = directory
            .appendingPathComponent("scally-output-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)

        try OutputWriter.write(buffer: finalBuffer, to: outputURL, format: format,
                               sharpener: sharpener, faces: faces)

        return UpscaleResult(
            outputURL: outputURL,
            outputWidth: finalBuffer.width,
            outputHeight: finalBuffer.height,
            appliedScale: effectiveScale,
            requestedScale: requestedScale,
            duration: Date().timeIntervalSince(started)
        )
    }

    private static func downsample(_ buffer: MappedPixelBuffer,
                                   to size: (width: Int, height: Int),
                                   directory: URL) throws -> MappedPixelBuffer {
        let output = try MappedPixelBuffer(width: size.width, height: size.height,
                                           directory: directory)
        var source = vImage_Buffer(data: buffer.baseAddress,
                                   height: vImagePixelCount(buffer.height),
                                   width: vImagePixelCount(buffer.width),
                                   rowBytes: buffer.bytesPerRow)
        var destination = vImage_Buffer(data: output.baseAddress,
                                        height: vImagePixelCount(output.height),
                                        width: vImagePixelCount(output.width),
                                        rowBytes: output.bytesPerRow)
        vImageScale_ARGB8888(&source, &destination, nil,
                             vImage_Flags(kvImageHighQualityResampling))
        return output
    }
}
