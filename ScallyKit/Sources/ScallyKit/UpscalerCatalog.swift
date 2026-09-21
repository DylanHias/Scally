import Foundation
import CoreML

/// The model Scally ships.
///
/// There is one. The four-way comparison this type used to carry is gone along
/// with the other three models: `4xNomosWebPhoto_RealPLKSR` has the same
/// training data as the ESRGAN Nomos it replaces, less than half the
/// parameters, and a permissive licence.
public struct UpscalerOption: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let parameters: String

    public func makeUpscaler(computeUnits: MLComputeUnits = .all) throws -> any Upscaler {
        try CoreMLUpscaler(modelName: id, computeUnits: computeUnits)
    }

    public static let all: [UpscalerOption] = [
        UpscalerOption(id: "NomosPLKSR", title: "Nomos PLKSR",
                       detail: "RealPLKSR, trained on realistic web-photo degradation.",
                       parameters: "7.4M"),
    ]

    public static var `default`: UpscalerOption { all[0] }
}
