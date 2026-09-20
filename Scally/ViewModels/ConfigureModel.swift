import Foundation
import ScallyKit

/// Everything the Configure screen states while the user still has a decision
/// to make: resulting dimensions, estimated file size, estimated time, and
/// whether a scale is affordable on this device.
///
/// Kept separate from the view so the memory-clamp path - the app's most
/// important safety behaviour - is testable without a simulator.
struct ConfigureModel {
    let inputWidth: Int
    let inputHeight: Int
    let inputBytes: Int
    let budget: MemoryBudget

    static let offeredScales = [2, 4]

    /// Seconds per 256x256 tile.
    ///
    /// Measured 2026-09-20 on an iPhone 17 Pro, Release build, RealESRGAN
    /// x4plus on the Neural Engine: 143 ms/tile (GPU 683 ms, CPU 1026 ms).
    /// A little headroom is added because older devices are slower and the
    /// first tile carries model load.
    ///
    /// The design's own estimates ("6 s" for a 240px image, "22 s" for a 12MP
    /// one) imply per-tile rates roughly 60x apart, so they are illustrative
    /// rather than literal.
    static let secondsPerTile = 0.16
    private static let tileSize = 256
    private static let overlap = 16

    init(inputWidth: Int, inputHeight: Int, inputBytes: Int = 0, budget: MemoryBudget = .current()) {
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.inputBytes = inputBytes
        self.budget = budget
    }

    func outputDimensions(scale: Int) -> (width: Int, height: Int) {
        (inputWidth * scale, inputHeight * scale)
    }

    /// Rough encoded size. HEIC lands near 0.35 bytes per pixel at our quality.
    /// For setting expectations, not accounting.
    func estimatedBytes(scale: Int) -> Int {
        let size = outputDimensions(scale: scale)
        return Int(Double(size.width * size.height) * 0.35)
    }

    /// The model always runs at 4x, so tile count never depends on the
    /// requested scale - a 2x request does the same work then downsamples.
    var tileCount: Int {
        let step = Self.tileSize - Self.overlap
        let columns = max(1, Int(ceil(Double(max(0, inputWidth - Self.tileSize)) / Double(step))) + 1)
        let rows = max(1, Int(ceil(Double(max(0, inputHeight - Self.tileSize)) / Double(step))) + 1)
        return columns * rows
    }

    func estimatedSeconds(scale: Int) -> Int {
        max(1, Int((Double(tileCount) * Self.secondsPerTile).rounded()))
    }

    func isAvailable(scale: Int) -> Bool {
        budget.resolveScale(requested: scale, inputWidth: inputWidth, inputHeight: inputHeight)
            == .granted(scale: scale)
    }

    /// The design's wording, with the real requirement rather than a fixed
    /// figure: "4× would need 1.9 GB of memory - more than this iPhone can give
    /// a single app. 2× is available."
    func unavailableReason(scale: Int) -> String? {
        guard !isAvailable(scale: scale) else { return nil }
        let bytes = MemoryBudget.outputBytes(width: inputWidth, height: inputHeight, scale: scale)
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
        let alternatives = Self.offeredScales.filter { $0 < scale && isAvailable(scale: $0) }

        var message = "\(scale)× would need \(formatted) of memory, more than this iPhone can give a single app."
        if let best = alternatives.max() {
            message += " \(best)× is available."
        }
        return message
    }

    var availableScales: [Int] { Self.offeredScales.filter { isAvailable(scale: $0) } }

    var defaultScale: Int { availableScales.max() ?? 2 }

    var canUpscaleAtAll: Bool { !availableScales.isEmpty }
}
