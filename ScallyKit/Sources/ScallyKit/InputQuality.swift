import Foundation

/// Whether an image is degraded enough for the model to be worth running.
///
/// This exists because of a measurement that is easy to miss: on a photograph
/// that is already clean, the model makes it **worse**. Measured at 2x against
/// the original as ground truth, on four photographs, comparing the model's
/// output to a plain high-quality resample of the same input:
///
///     input                 model vs resample
///     pristine, no JPEG           -3.87 dB
///     JPEG 90                     -1.41 dB
///     JPEG 75                     -0.65 dB
///     JPEG 60                     +0.29 dB
///     JPEG 30                     +0.57 dB
///     JPEG 20                     +0.86 dB
///     gaussian blur 1.0           +0.09 dB
///     gaussian blur 1.8           +1.13 dB
///     noise sigma 6               +3.75 dB
///
/// Super-resolution models are trained on heavily degraded inputs. Given a
/// clean one they "repair" damage that is not there, stripping real texture as
/// though it were noise and substituting their own - which is precisely the
/// digitally-modified look this app is trying to avoid. So the honest thing is
/// to not run it.
///
/// Three cheap signals decide. None is sufficient alone: blockiness misses
/// noise entirely, and a high-frequency measure reads noise and real detail
/// the same way round.
public struct InputQuality: Sendable {
    /// Pixel discontinuity across 8-pixel boundaries against the discontinuity
    /// within them. JPEG compresses in 8x8 blocks, so its artefacts show here
    /// and nowhere else. 1.0 is a clean image.
    public let blockiness: Double

    /// High-frequency energy relative to mid-frequency energy - the mean
    /// absolute Laplacian over the mean absolute gradient.
    ///
    /// Deliberately a *ratio*. The obvious measure, absolute Laplacian, is
    /// content-dependent: a photograph of a smooth subject or a shallow depth
    /// of field scores as low as a blurred one, and the first build of this
    /// sent a perfectly clean portrait to the model on exactly that mistake.
    /// Blurring strips high frequencies while leaving mid ones, so this ratio
    /// falls; a smooth subject loses both, so it does not. Around 1.0 for a
    /// sharp image, 0.59 at gaussian blur 1.0, 0.40 at blur 1.8.
    public let sharpness: Double

    /// The same high-frequency energy, but measured only in the flattest fifth
    /// of the image. Real detail is structured and lives in busy regions;
    /// sensor noise is everywhere, including in the sky.
    public let noise: Double

    /// Thresholds fitted to the table above: eleven degradation cases across
    /// four photographs, all eleven classified correctly.
    ///
    /// A rule fitted to a small sample, not a law, and deliberately biased
    /// towards *not* running the model: the penalty for running it needlessly
    /// is nearly four decibels, while the reward for running it correctly is
    /// often under one.
    public var needsRestoration: Bool {
        blockiness > 1.8 || sharpness < 0.70 || noise > 4.0
    }

    /// Why the decision went the way it did, for the log and the UI.
    public var reason: String {
        if blockiness > 1.8 { return "compression artefacts" }
        if sharpness < 0.70 { return "soft detail" }
        if noise > 4.0 { return "sensor noise" }
        return "already clean"
    }

    public static func measure(_ image: LoadedImage) -> InputQuality {
        let width = image.width, height = image.height
        guard width > 18, height > 18 else {
            // Too small to measure; assume it wants the model.
            return InputQuality(blockiness: 2, sharpness: 0, noise: 0)
        }

        var luma = [Double](repeating: 0, count: width * height)
        image.pixels.withUnsafeBufferPointer { raw in
            for index in 0..<(width * height) {
                let p = index * 4
                luma[index] = 0.299 * Double(raw[p]) + 0.587 * Double(raw[p + 1])
                            + 0.114 * Double(raw[p + 2])
            }
        }

        // Blockiness: horizontal differences on and off the 8-pixel grid.
        var onEdge = 0.0, onCount = 0.0, offEdge = 0.0, offCount = 0.0
        for y in 0..<height {
            let row = y * width
            for x in 1..<width {
                let delta = abs(luma[row + x] - luma[row + x - 1])
                if x % 8 == 0 { onEdge += delta; onCount += 1 }
                else { offEdge += delta; offCount += 1 }
            }
        }
        let blockiness = (offCount > 0 && offEdge > 0)
            ? (onEdge / max(onCount, 1)) / (offEdge / offCount) : 1

        // Laplacian magnitude, and the local standard deviation, per 16x16
        // block. The flattest blocks carry the noise floor.
        let block = 16
        let blocksX = (width - 2) / block, blocksY = (height - 2) / block
        var highFrequency = [Double](), deviation = [Double]()
        highFrequency.reserveCapacity(blocksX * blocksY)
        deviation.reserveCapacity(blocksX * blocksY)
        var laplacianTotal = 0.0, gradientTotal = 0.0, sampleCount = 0.0

        for by in 0..<blocksY {
            for bx in 0..<blocksX {
                var sumAbs = 0.0, sum = 0.0, sumSquares = 0.0, sumGradient = 0.0
                for y in (by * block + 1)..<(by * block + block + 1) {
                    for x in (bx * block + 1)..<(bx * block + block + 1) {
                        let i = y * width + x
                        let lap = -4 * luma[i] + luma[i - 1] + luma[i + 1]
                                + luma[i - width] + luma[i + width]
                        sumAbs += abs(lap)
                        sumGradient += abs(luma[i] - luma[i - 1])
                                     + abs(luma[i] - luma[i - width])
                        sum += luma[i]
                        sumSquares += luma[i] * luma[i]
                    }
                }
                let n = Double(block * block)
                highFrequency.append(sumAbs / n)
                deviation.append(max(0, sumSquares / n - (sum / n) * (sum / n)).squareRoot())
                laplacianTotal += sumAbs
                gradientTotal += sumGradient
                sampleCount += n
            }
        }
        guard !highFrequency.isEmpty, gradientTotal > 0 else {
            return InputQuality(blockiness: blockiness, sharpness: 1, noise: 0)
        }

        let ranked = deviation.enumerated().sorted { $0.element < $1.element }
        let flatCount = max(1, ranked.count / 5)
        let noise = ranked.prefix(flatCount)
            .reduce(0.0) { $0 + highFrequency[$1.offset] } / Double(flatCount)

        _ = sampleCount
        return InputQuality(blockiness: blockiness,
                            sharpness: laplacianTotal / gradientTotal,
                            noise: noise)
    }
}
