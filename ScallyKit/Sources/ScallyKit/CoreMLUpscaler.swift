import Foundation
import CoreML

/// Runs Real-ESRGAN realesr-general-x4v3 on one tile at a time.
///
/// Model weights are BSD-3-Clause (Xintao Wang et al.); the app must reproduce
/// that notice - see the Licenses screen.
public final class CoreMLUpscaler: Upscaler, @unchecked Sendable {
    public let scale = 4

    static let tileSize = 256
    private let model: MLModel

    public init(computeUnits: MLComputeUnits = .all) throws {
        guard let url = Bundle.module.url(forResource: "RealESRGANx4", withExtension: "mlmodelc")
                ?? Bundle.module.url(forResource: "RealESRGANx4", withExtension: "mlpackage") else {
            throw UpscaleError.modelUnavailable
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        do {
            // An .mlpackage must be compiled before it can be loaded.
            let compiled = url.pathExtension == "mlpackage"
                ? try MLModel.compileModel(at: url)
                : url
            self.model = try MLModel(contentsOf: compiled, configuration: configuration)
        } catch {
            throw UpscaleError.modelUnavailable
        }
    }

    public func upscale(tile: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> TilePixels {
        let padded = Self.reflectPad(
            UnsafeBufferPointer(start: tile.assumingMemoryBound(to: UInt8.self),
                                count: bytesPerRow * height),
            width: width, height: height, bytesPerRow: bytesPerRow, to: Self.tileSize
        )

        let input = try MLMultiArray(
            shape: [1, 3, NSNumber(value: Self.tileSize), NSNumber(value: Self.tileSize)],
            dataType: .float32
        )
        let inputPointer = input.dataPointer.assumingMemoryBound(to: Float32.self)
        let plane = Self.tileSize * Self.tileSize
        for y in 0..<Self.tileSize {
            for x in 0..<Self.tileSize {
                let source = (y * Self.tileSize + x) * 4
                let offset = y * Self.tileSize + x
                inputPointer[offset] = Float32(padded[source]) / 255.0
                inputPointer[plane + offset] = Float32(padded[source + 1]) / 255.0
                inputPointer[2 * plane + offset] = Float32(padded[source + 2]) / 255.0
            }
        }

        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["input": MLFeatureValue(multiArray: input)]
        )
        guard let output = try? model.prediction(from: provider),
              let array = output.featureValue(for: "output")?.multiArrayValue else {
            throw UpscaleError.inferenceFailed(tileIndex: -1)
        }

        let outputSize = Self.tileSize * scale
        let outputPointer = array.dataPointer.assumingMemoryBound(to: Float32.self)
        let outputPlane = outputSize * outputSize

        // Crop straight back to the scaled size of the real (unpadded) tile.
        let cropWidth = width * scale
        let cropHeight = height * scale
        var pixels = [UInt8](repeating: 255, count: cropWidth * cropHeight * 4)

        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let source = y * outputSize + x
                let destination = (y * cropWidth + x) * 4
                pixels[destination] = Self.clampToByte(outputPointer[source])
                pixels[destination + 1] = Self.clampToByte(outputPointer[outputPlane + source])
                pixels[destination + 2] = Self.clampToByte(outputPointer[2 * outputPlane + source])
                pixels[destination + 3] = 255
            }
        }

        return TilePixels(pixels: pixels, width: cropWidth, height: cropHeight,
                          bytesPerRow: cropWidth * 4)
    }

    private static func clampToByte(_ value: Float32) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

    /// Mirrors edge pixels outward to fill a `size` x `size` tile.
    ///
    /// Zero padding would put black inside the model's receptive field and
    /// leave a dark fringe along every border of the finished image.
    static func reflectPad(_ source: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                           bytesPerRow: Int, to size: Int) -> [UInt8] {
        var padded = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            let sourceY = reflect(y, limit: height)
            for x in 0..<size {
                let sourceX = reflect(x, limit: width)
                let from = sourceY * bytesPerRow + sourceX * 4
                let to = (y * size + x) * 4
                padded[to] = source[from]
                padded[to + 1] = source[from + 1]
                padded[to + 2] = source[from + 2]
                padded[to + 3] = source[from + 3]
            }
        }
        return padded
    }

    /// Array-form convenience used by tests.
    static func reflectPad(_ source: [UInt8], width: Int, height: Int,
                           bytesPerRow: Int, to size: Int) -> [UInt8] {
        source.withUnsafeBufferPointer {
            reflectPad($0, width: width, height: height, bytesPerRow: bytesPerRow, to: size)
        }
    }

    private static func reflect(_ index: Int, limit: Int) -> Int {
        guard limit > 1 else { return 0 }
        let period = 2 * limit - 2
        var wrapped = index % period
        if wrapped < 0 { wrapped += period }
        return wrapped < limit ? wrapped : period - wrapped
    }
}
