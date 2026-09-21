import Foundation
import CoreGraphics
import Vision

/// Where the faces are, as fractions of the image.
///
/// Normalised on purpose. The pipeline detects on the *input* - a 240x240
/// thumbnail rather than its 960x960 enlargement - and the same rectangles
/// then describe the intermediate buffer, the downsampled result and the final
/// image without any scale bookkeeping. Faces are large features; there is
/// nothing to gain from looking for them at 4x the pixels and 16x the cost.
public struct FaceRegions: Sendable {
    /// Rectangles in a top-left origin space, each component in 0...1.
    public let rectangles: [CGRect]

    public static let none = FaceRegions(rectangles: [])
    public var isEmpty: Bool { rectangles.isEmpty }

    public init(rectangles: [CGRect]) {
        self.rectangles = rectangles
    }
}

public protocol FaceDetecting: Sendable {
    func regions(in image: CGImage) -> FaceRegions
}

/// Finds nothing. The default, so the pipeline's behaviour is unchanged unless
/// a caller asks for face awareness.
public struct NoFaceDetector: FaceDetecting {
    public init() {}
    public func regions(in image: CGImage) -> FaceRegions { .none }
}

/// Apple's Vision framework.
///
/// Chosen over every open face model on licensing grounds, and the reasoning
/// is worth keeping: CodeFormer is S-Lab 1.0 non-commercial, GFPGAN wears an
/// Apache-2.0 badge while its own acknowledgements credit DFDNet
/// (CC BY-NC-SA) and StyleGAN2 (NVIDIA NC), and nearly everything else traces
/// back to FFHQ, which is CC BY-NC-SA 4.0. Scally's only other model is
/// CC BY 4.0, so adopting any of them would re-encumber an app that is
/// currently free of non-commercial terms. Vision ships with the OS, costs
/// nothing, adds no bytes, and does not need a licence screen.
///
/// It also does something different from those models, deliberately. They
/// *generate* a face. This only says where one is, so the pipeline can be
/// gentler there - which is what "Faces stay as they are" actually requires.
public struct VisionFaceDetector: FaceDetecting {
    public init() {}

    public func regions(in image: CGImage) -> FaceRegions {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // A detector that fails is a detector that found nothing. It must
            // never fail the upscale - this is a refinement, not a step.
            return .none
        }
        guard let observations = request.results, !observations.isEmpty else { return .none }

        return FaceRegions(rectangles: observations.map { observation in
            // Vision's origin is bottom-left; everything else here is top-left.
            let box = observation.boundingBox
            return CGRect(x: box.minX, y: 1 - box.maxY,
                          width: box.width, height: box.height)
        })
    }
}
