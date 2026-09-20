import Foundation

public enum UpscaleError: Error, LocalizedError, Equatable {
    case unsupportedImageFormat
    case imageTooLarge(pixels: Int)
    case scratchAllocationFailed(underlying: Int32)
    case modelUnavailable
    case inferenceFailed(tileIndex: Int)
    case encodingFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedImageFormat: "That image format isn't supported."
        case .imageTooLarge(let pixels): "That image is too large to process (\(pixels) pixels)."
        case .scratchAllocationFailed(let code): "Couldn't allocate working storage (errno \(code))."
        case .modelUnavailable: "The upscaling model failed to load."
        case .inferenceFailed(let index): "Upscaling failed on tile \(index)."
        case .encodingFailed: "Couldn't write the finished image."
        case .cancelled: "Cancelled."
        }
    }
}
