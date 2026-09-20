import Foundation

/// RGBA8 pixels produced by an upscaler.
public struct TilePixels: Sendable {
    public let pixels: [UInt8]
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    public init(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }
}

public protocol Upscaler: Sendable {
    /// Linear magnification factor applied to both axes.
    var scale: Int { get }

    func upscale(tile: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> TilePixels
}

/// Copies its input unchanged. Exists so the tiler and composer can be proven
/// correct without a model in the loop; see ReconstructionTests.
public struct IdentityUpscaler: Upscaler {
    public let scale = 1
    public init() {}

    public func upscale(tile: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> TilePixels {
        let source = tile.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for byte in 0..<(width * 4) {
                pixels[row * width * 4 + byte] = source[row * bytesPerRow + byte]
            }
        }
        return TilePixels(pixels: pixels, width: width, height: height, bytesPerRow: width * 4)
    }
}
