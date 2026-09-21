import Foundation
import CoreML

/// The models bundled for head-to-head comparison on device.
///
/// The three convolutional entries share one graph shape, so they differ only
/// in weights and training data - which in this space usually matters more
/// than parameter count.
public struct UpscalerOption: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let parameters: String
    public let isDiffusion: Bool

    public func makeUpscaler(computeUnits: MLComputeUnits = .all) throws -> any Upscaler {
        isDiffusion
            ? try ResShiftUpscaler(computeUnits: computeUnits)
            : try CoreMLUpscaler(modelName: id, computeUnits: computeUnits)
    }

    public static let all: [UpscalerOption] = [
        UpscalerOption(id: "GeneralX4v3", title: "General v3",
                       detail: "Small and fast. Weakest on clean photos.",
                       parameters: "1.2M", isDiffusion: false),
        UpscalerOption(id: "RealESRGANx4", title: "Real-ESRGAN",
                       detail: "The general-purpose baseline.",
                       parameters: "16.7M", isDiffusion: false),
        UpscalerOption(id: "NomosWebPhoto", title: "Nomos Web Photo",
                       detail: "Same graph, fine-tuned on JPEG/WebP recompression.",
                       parameters: "16.7M", isDiffusion: false),
        UpscalerOption(id: "ScallyDiffusion", title: "Diffusion",
                       detail: "One-step ResShift. Invents detail, much slower.",
                       parameters: "118.6M", isDiffusion: true),
    ]
}
