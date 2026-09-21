import Foundation
import CoreML

/// The models Scally bundles, and which one it runs.
///
/// All three are convolutional, and that is not a coincidence. Window-attention
/// models - DAT2 and DRCT-L were both measured - are rejected outright by the
/// Neural Engine compiler (`ANECCompile() FAILED`), leaving them 6-13x slower
/// on GPU and over 100 MB each. DAT2 would not run at all under the default
/// compute units.
///
/// Among the convolutional models the ordering is not by size. Measured per
/// 256x256 tile:
///
///     ESRGAN 16.7M   145 ms on ANE   380 ms CPU+GPU
///     PLKSR   7.4M   186 ms on ANE   101 ms CPU+GPU
///     MoSR    4.3M   102 ms on ANE    72 ms CPU+GPU
///
/// The largest model is the fastest one on the Neural Engine, and the two
/// smaller ones are *slower* on it than off it. RRDBNet is 3x3 convolutions
/// throughout, which is what the ANE is built for; PLKSR's 17x17 partial large
/// kernel is not, so its ANE path is worse than no ANE at all.
public struct UpscalerOption: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let parameters: String

    public func makeUpscaler(computeUnits: MLComputeUnits = .all) throws -> any Upscaler {
        try CoreMLUpscaler(modelName: id, computeUnits: computeUnits)
    }

    /// What the pipeline runs unless told otherwise.
    public static let shipping = UpscalerOption(
        id: "NomosWebPhoto", title: "Nomos Web Photo",
        detail: "RRDBNet, trained on realistic web-photo degradation.",
        parameters: "16.7M")

    public static let all: [UpscalerOption] = [
        shipping,
        UpscalerOption(id: "NomosPLKSR", title: "Nomos PLKSR",
                       detail: "Same training data, RealPLKSR backbone. Poor ANE fit.",
                       parameters: "7.4M"),
        UpscalerOption(id: "MoSR", title: "MoSR",
                       detail: "Smallest and quickest. Least capacity.",
                       parameters: "4.3M"),
    ]
}
