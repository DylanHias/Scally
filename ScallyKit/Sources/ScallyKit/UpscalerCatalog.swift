import Foundation
import CoreML

/// The models Scally bundles, chosen by measurement rather than reputation.
///
/// `tools/benchmark_models.py` scores every candidate against real
/// photographs: a 1024x1024 crop is downsampled 4x, softened and JPEG'd the
/// way a phone photo actually is, and each model is asked to put it back. On
/// that realistic input, per 256x256 tile:
///
///     model          ANE     PSNR    SSIM   detail
///     RealESRNet    172ms   32.28  0.8973   0.16x
///     Lanczos         -     31.72  0.8904   0.16x
///     MoSR_mssim    110ms   31.36  0.8814   0.23x
///     SPAN_mssim     16ms   29.79  0.8710   0.31x
///     DRCT-L       1180ms   30.39  0.8736   0.27x
///     NomosPLKSR    170ms   29.92  0.8455   1.33x
///     NomosWebPhoto 160ms   29.08  0.8443   1.26x
///
/// `detail` is the mean absolute Laplacian of the output over that of the
/// original: 1.00 means the model resolved exactly what the camera did. Every
/// adversarially-trained model sits above it - they invent texture that was
/// never photographed, which is what reads as "digitalised" on a real
/// photograph. They are not bundled.
///
/// Two further results worth not re-discovering. Size buys nothing: DRCT-L at
/// 27.6M parameters scores below MoSR at 4.3M while being eleven times
/// slower. And window attention is refused outright by the Neural Engine
/// compiler, so every transformer runs on the GPU at 1-2 seconds per tile.
public struct UpscalerOption: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let parameters: String

    public func makeUpscaler(computeUnits: MLComputeUnits = .all) throws -> any Upscaler {
        try CoreMLUpscaler(modelName: id, computeUnits: computeUnits)
    }

    /// What the pipeline runs unless told otherwise: the most faithful of the
    /// measured set on realistic input.
    public static let shipping = UpscalerOption(
        id: "RealESRNet", title: "Real-ESRNet",
        detail: "Most faithful. No adversarial loss, so nothing is invented.",
        parameters: "16.7M")

    public static let all: [UpscalerOption] = [
        shipping,
        UpscalerOption(id: "MoSR_mssim", title: "MoSR",
                       detail: "Resolves a little more, 1.6x quicker. Can show blocking.",
                       parameters: "4.3M"),
        UpscalerOption(id: "SPAN_mssim", title: "SPAN",
                       detail: "Ten times quicker than the rest. Least faithful of the three.",
                       parameters: "2.2M"),
    ]
}
