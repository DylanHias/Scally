import Foundation
import CoreML
import Accelerate

/// One-step diffusion super-resolution: RSD, a student distilled from a
/// 15-step ResShift teacher (arXiv 2503.13358).
///
/// Unlike a convolutional upscaler this one *invents* detail rather than
/// sharpening what survived, which is the whole reason it is here.
///
/// Three models per tile:
///   1. VQ encoder  - bicubic 4x of the 64x64 LQ tile, encoded to a 64x64x3 latent
///   2. UNet        - a single denoising step, conditioned on the LQ in PIXEL space
///   3. VQ decoder  - latent back to a 256x256 RGB tile
///
/// **Licence: non-commercial.** ResShift is S-Lab License 1.0 and RSD is
/// CC BY-NC-SA 4.0. Shipping this keeps Scally free permanently.
public final class ResShiftUpscaler: Upscaler, @unchecked Sendable {
    public let scale = 4
    public let inputTileSize = 64

    /// Constants read out of the reference diffusion object, not guessed.
    /// T = timesteps_with_zeros[0], kappa = 2.0, sqrt_etas[T] = 0.99.
    private enum Sampling {
        static let timestep: Float = 14
        /// kappa * sqrt_etas[T]
        static let priorNoiseScale: Float = 1.98
        /// sqrt(etas[T] * kappa^2 + 1), the `_scale_input` divisor for latents
        static let inputStd: Float = 2.2181974664
    }

    private let encoder: MLModel
    private let unet: MLModel
    private let decoder: MLModel
    private let latent = 64
    private let outputTile = 256

    public init(computeUnits: MLComputeUnits = .all) throws {
        func load(_ name: String) throws -> MLModel {
            guard let url = Bundle.module.url(forResource: name, withExtension: "mlmodelc")
                    ?? Bundle.module.url(forResource: name, withExtension: "mlpackage") else {
                throw UpscaleError.modelUnavailable
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = computeUnits
            let compiled = url.pathExtension == "mlpackage"
                ? try MLModel.compileModel(at: url) : url
            return try MLModel(contentsOf: compiled, configuration: configuration)
        }
        do {
            encoder = try load("VQEncoder")
            unet = try load("RSD4x")
            decoder = try load("VQDecoder")
        } catch {
            throw UpscaleError.modelUnavailable
        }
    }

    public func upscale(tile: UnsafeRawPointer, width: Int, height: Int,
                        bytesPerRow: Int) throws -> TilePixels {
        // Edge tiles are reflect-padded to the full 64x64 the model requires,
        // then cropped back, exactly as the CNN path does.
        let padded = CoreMLUpscaler.reflectPad(
            UnsafeBufferPointer(start: tile.assumingMemoryBound(to: UInt8.self),
                                count: bytesPerRow * height),
            width: width, height: height, bytesPerRow: bytesPerRow, to: inputTileSize
        )

        // 1. LQ in pixel space, [-1, 1]. This is what conditions the UNet -
        //    at its ORIGINAL resolution, not the latent. An f=4 latent of the
        //    4x-upsampled image happens to be exactly this size.
        let lqPlanes = Self.planes(fromRGBA: padded, edge: inputTileSize)

        // 2. Bicubic 4x, then encode.
        let upsampled = try Self.resampleRGBA(padded, from: inputTileSize, to: outputTile)
        let encoded = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(multiArray: try Self.array(
                Self.planes(fromRGBA: upsampled, edge: outputTile),
                shape: [1, 3, outputTile, outputTile]))
        ]))
        guard let zY = encoded.featureValue(for: "latent")?.multiArrayValue else {
            throw UpscaleError.inferenceFailed(tileIndex: -1)
        }

        // 3. Prior sample: z_T = z_y + kappa * sqrt_etas[T] * noise, then the
        //    `_scale_input` normalisation the model was trained with.
        let count = 3 * latent * latent
        let zPointer = zY.dataPointer.assumingMemoryBound(to: Float.self)
        var x = [Float](repeating: 0, count: count)
        var generator = GaussianNoise()
        for i in 0..<count {
            x[i] = (zPointer[i] + Sampling.priorNoiseScale * generator.next()) / Sampling.inputStd
        }

        var stochastic = [Float](repeating: 0, count: latent * latent)
        for i in 0..<stochastic.count { stochastic[i] = generator.next() }

        // 4. The single denoising step.
        let prediction = try unet.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "x": MLFeatureValue(multiArray: try Self.array(x, shape: [1, 3, latent, latent])),
            "timesteps": MLFeatureValue(multiArray: try Self.array([Sampling.timestep], shape: [1])),
            "lq": MLFeatureValue(multiArray: try Self.array(lqPlanes, shape: [1, 3, latent, latent])),
            "noise_input": MLFeatureValue(multiArray: try Self.array(stochastic, shape: [1, 1, latent, latent])),
        ]))
        guard let predicted = prediction.featureValue(for: "out")?.multiArrayValue else {
            throw UpscaleError.inferenceFailed(tileIndex: -1)
        }

        // 5. Decode back to pixels.
        let decoded = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "latent": MLFeatureValue(multiArray: predicted)
        ]))
        guard let image = decoded.featureValue(for: "image")?.multiArrayValue else {
            throw UpscaleError.inferenceFailed(tileIndex: -1)
        }

        return Self.rgba(fromPlanes: image, edge: outputTile,
                         cropWidth: width * scale, cropHeight: height * scale)
    }

    // MARK: - Conversions

    /// RGBA8 -> planar RGB in [-1, 1], the range every one of these models uses.
    private static func planes(fromRGBA rgba: [UInt8], edge: Int) -> [Float] {
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

    private static func rgba(fromPlanes array: MLMultiArray, edge: Int,
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

    private static func array(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .float32)
        let p = a.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<values.count { p[i] = values[i] }
        return a
    }

    /// High-quality resample of an RGBA tile. The reference uses bicubic and
    /// vImage gives Lanczos; the difference only affects the conditioning
    /// image, which the model is tolerant of.
    private static func resampleRGBA(_ source: [UInt8], from: Int, to: Int) throws -> [UInt8] {
        var input = source
        var output = [UInt8](repeating: 0, count: to * to * 4)
        input.withUnsafeMutableBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                var src = vImage_Buffer(data: inBuf.baseAddress,
                                        height: vImagePixelCount(from),
                                        width: vImagePixelCount(from), rowBytes: from * 4)
                var dst = vImage_Buffer(data: outBuf.baseAddress,
                                        height: vImagePixelCount(to),
                                        width: vImagePixelCount(to), rowBytes: to * 4)
                vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return output
    }
}

/// Box-Muller gaussian. The model is stochastic by design, so this feeds both
/// the prior sample and the extra noise channel.
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
