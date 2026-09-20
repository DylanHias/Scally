import Foundation
import SwiftData

/// One completed upscale.
///
/// Both input and output dimensions are stored because the design shows them
/// together everywhere - "240x240 -> 960x960" in history, INPUT/OUTPUT rows on
/// the result screen - and because press-and-hold compares against the real
/// original rather than a re-derived approximation.
@Model
final class UpscaleRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var originalFilename: String
    var appliedScale: Int
    var requestedScale: Int
    var inputWidth: Int
    var inputHeight: Int
    var outputWidth: Int
    var outputHeight: Int
    var inputBytes: Int
    var outputBytes: Int
    var duration: TimeInterval
    var inputExtension: String
    var outputExtension: String

    init(id: UUID = UUID(),
         createdAt: Date = .now,
         originalFilename: String,
         appliedScale: Int,
         requestedScale: Int,
         inputWidth: Int,
         inputHeight: Int,
         outputWidth: Int,
         outputHeight: Int,
         inputBytes: Int,
         outputBytes: Int,
         duration: TimeInterval,
         inputExtension: String,
         outputExtension: String) {
        self.id = id
        self.createdAt = createdAt
        self.originalFilename = originalFilename
        self.appliedScale = appliedScale
        self.requestedScale = requestedScale
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.duration = duration
        self.inputExtension = inputExtension
        self.outputExtension = outputExtension
    }

    var wasClamped: Bool { appliedScale != requestedScale }

    /// "240x240 -> 960x960", as the history rows render it.
    var dimensionSummary: String {
        "\(inputWidth)x\(inputHeight) -> \(outputWidth)x\(outputHeight)"
    }

    var totalBytes: Int { inputBytes + outputBytes }
}
