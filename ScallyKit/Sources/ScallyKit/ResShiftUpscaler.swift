import Foundation
import CoreML
import Accelerate

/// One-step diffusion super-resolution: RSD, a student distilled from a
/// 15-step ResShift teacher (arXiv 2503.13358).
///
/// Unlike a convolutional upscaler this one *invents* detail rather than
/// sharpening what survived.
///
/// The encoder, the single denoising step and the decoder are fused into one
/// Core ML graph, along with the prior sample and the `_scale_input`
/// normalisation. Only the 4x resample stays here, because coremltools has no
/// `upsample_bicubic2d` and vImage does it well.
///
/// **Licence: non-commercial.** ResShift is S-Lab License 1.0 and RSD is
/// CC BY-NC-SA 4.0. Shipping this keeps Scally free permanently.
public final class ResShiftUpscaler: Upscaler, @unchecked Sendable {
    public let scale = 4
    public let inputTileSize = 64

    private let model: MLModel
    private let latent = 64
    private let outputTile = 256

    public init(computeUnits: MLComputeUnits = .all) throws {
        guard let url = Bundle.module.url(forResource: "ScallyDiffusion", withExtension: "mlmodelc")
                ?? Bundle.module.url(forResource: "ScallyDiffusion", withExtension: "mlpackage") else {
            throw UpscaleError.modelUnavailable
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        do {
            let compiled = url.pathExtension == "mlpackage"
                ? try MLModel.compileModel(at: url) : url
            model = try MLModel(contentsOf: compiled, configuration: configuration)
        } catch {
            throw UpscaleError.modelUnavailable
        }
    }

    public func upscale(tile: UnsafeRawPointer, width: Int, height: Int,
                        bytesPerRow: Int) throws -> TilePixels {
        // Edge tiles are reflect-padded up to the full 64x64 the model needs,
        // then cropped back. Zero padding would leave dark fringes.
        let padded = Self.reflectPad(
            UnsafeBufferPointer(start: tile.assumingMemoryBound(to: UInt8.self),
                                count: bytesPerRow * height),
            width: width, height: height, bytesPerRow: bytesPerRow, to: inputTileSize
        )
        let upsampled = Self.resampleRGBA(padded, from: inputTileSize, to: outputTile)

        var generator = GaussianNoise()
        var noise = [Float](repeating: 0, count: 3 * latent * latent)
        for i in 0..<noise.count { noise[i] = generator.next() }
        var stochastic = [Float](repeating: 0, count: latent * latent)
        for i in 0..<stochastic.count { stochastic[i] = generator.next() }

        let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "lqUpsampled": MLFeatureValue(multiArray: try Self.array(
                Self.planes(fromRGBA: upsampled, edge: outputTile),
                shape: [1, 3, outputTile, outputTile])),
            "lq": MLFeatureValue(multiArray: try Self.array(
                Self.planes(fromRGBA: padded, edge: inputTileSize),
                shape: [1, 3, latent, latent])),
            "noise": MLFeatureValue(multiArray: try Self.array(noise, shape: [1, 3, latent, latent])),
            "stochastic": MLFeatureValue(multiArray: try Self.array(stochastic, shape: [1, 1, latent, latent])),
        ]))
        guard let image = prediction.featureValue(for: "image")?.multiArrayValue else {
            throw UpscaleError.inferenceFailed(tileIndex: -1)
        }

        return Self.rgba(fromPlanes: image, edge: outputTile,
                         cropWidth: width * scale, cropHeight: height * scale)
    }

    // MARK: - Conversions

    /// RGBA8 -> planar RGB in [-1, 1], the range the model works in.
    static func planes(fromRGBA rgba: [UInt8], edge: Int) -> [Float] {
        var out = [Float](repeating: 0, count: 3 * edge * edge)
        let plane = edge * edge
        for y in 0..<edge {
            for x in 0..<edge {
                let s = (y * edge + x) * 4
                let d = y * edge + x
                out[d] = Float(rgba[s]) / 127.5 - 1
                out[plane + d] = Float(rgba[s + 1]) / 127.5 - 1
                out[2 * plane + d] = Float(rgba[s + 2]) / 127.5 - 1
            }
        }
        return out
    }

    static func rgba(fromPlanes array: MLMultiArray, edge: Int,
                     cropWidth: Int, cropHeight: Int) -> TilePixels {
        let p = array.dataPointer.assumingMemoryBound(to: Float.self)
        let plane = edge * edge
        var pixels = [UInt8](repeating: 255, count: cropWidth * cropHeight * 4)
        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let s = y * edge + x
                let d = (y * cropWidth + x) * 4
                pixels[d] = clamp(p[s])
                pixels[d + 1] = clamp(p[plane + s])
                pixels[d + 2] = clamp(p[2 * plane + s])
            }
        }
        return TilePixels(pixels: pixels, width: cropWidth, height: cropHeight,
                          bytesPerRow: cropWidth * 4)
    }

    private static func clamp(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, ((value + 1) * 127.5).rounded())))
    }

    static func array(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .float32)
        let p = a.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<values.count { p[i] = values[i] }
        return a
    }

    /// The reference upsamples bicubically; vImage gives Lanczos. The
    /// difference only affects the conditioning image, which the model
    /// tolerates - and its own noise moves the output ~25x more.
    static func resampleRGBA(_ source: [UInt8], from: Int, to: Int) -> [UInt8] {
        var input = source
        var output = [UInt8](repeating: 0, count: to * to * 4)
        input.withUnsafeMutableBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                var src = vImage_Buffer(data: inBuf.baseAddress, height: vImagePixelCount(from),
                                        width: vImagePixelCount(from), rowBytes: from * 4)
                var dst = vImage_Buffer(data: outBuf.baseAddress, height: vImagePixelCount(to),
                                        width: vImagePixelCount(to), rowBytes: to * 4)
                vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return output
    }

    /// Mirrors edge pixels outward to fill a `size` x `size` tile.
    static func reflectPad(_ source: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                           bytesPerRow: Int, to size: Int) -> [UInt8] {
        var padded = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            let sy = reflect(y, limit: height)
            for x in 0..<size {
                let sx = reflect(x, limit: width)
                let from = sy * bytesPerRow + sx * 4
                let to = (y * size + x) * 4
                padded[to] = source[from]
                padded[to + 1] = source[from + 1]
                padded[to + 2] = source[from + 2]
                padded[to + 3] = source[from + 3]
            }
        }
        return padded
    }

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

/// Box-Muller gaussian; the model is stochastic by design.
struct GaussianNoise {
    private var spare: Float?

    mutating func next() -> Float {
        if let value = spare { spare = nil; return value }
        var u: Float = 0, v: Float = 0, s: Float = 0
        repeat {
            u = Float.random(in: -1...1)
            v = Float.random(in: -1...1)
            s = u * u + v * v
        } while s >= 1 || s == 0
        let factor = (-2 * log(s) / s).squareRoot()
        spare = v * factor
        return u * factor
    }
}
