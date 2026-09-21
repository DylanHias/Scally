import Foundation
import CoreML

/// The models Scally bundles, and which one it runs.
///
/// **The loss function matters more than the architecture.** Every model here
/// is convolutional, because window attention is rejected outright by the
/// Neural Engine compiler - DAT2 and DRCT-L were both measured at 1110 ms and
/// 2208 ms per tile against ESRGAN's 145 ms on the ANE. But among the
/// convolutional models, what separates them for a photograph is not size or
/// speed, it is whether they were trained adversarially.
///
/// A GAN-trained model is rewarded for producing output that *looks* like a
/// sharp photograph, which in practice means inventing high-frequency texture:
/// hair strands that were never resolved, foliage detail that was never
/// recorded. On a genuinely degraded image that is a rescue. On a decent one
/// it reads as digitally sharpened - "modified", in the words of the person
/// this app is for - and it contradicts what the Configure screen promises:
/// detail is reconstructed, not invented.
///
/// `RealESRNet` is the same RRDBNet as `NomosWebPhoto`, the same 16.7M
/// weights, trained with L1 alone. It is therefore the same speed on the ANE
/// and does not hallucinate. It ships.
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
        id: "RealESRNet", title: "Real-ESRNet",
        detail: "No adversarial loss. Resolves detail, never invents it.",
        parameters: "16.7M")

    public static let all: [UpscalerOption] = [
        shipping,
        UpscalerOption(id: "NomosWebPhoto", title: "Nomos Web Photo",
                       detail: "GAN-trained. Sharper, and visibly manufactured.",
                       parameters: "16.7M"),
        UpscalerOption(id: "NomosPLKSR", title: "Nomos PLKSR",
                       detail: "GAN-trained, most aggressive. Poor ANE fit.",
                       parameters: "7.4M"),
        UpscalerOption(id: "MoSR", title: "MoSR",
                       detail: "GAN-trained. Smallest and quickest.",
                       parameters: "4.3M"),
    ]
}
