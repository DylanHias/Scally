import Testing
import Foundation
@testable import ScallyKit

@Test func reflectPaddingMirrorsEdgePixelsRatherThanZeroFilling() {
    let source: [UInt8] = [10, 10, 10, 255,  20, 20, 20, 255]
    let padded = CoreMLUpscaler.reflectPad(source, width: 2, height: 1, bytesPerRow: 8, to: 4)
    for y in 0..<4 {
        for x in 0..<4 {
            #expect(padded[(y * 4 + x) * 4] != 0,
                    "zero at \(x),\(y) - padding must reflect, not zero-fill")
        }
    }
}

@Test func reflectPaddingPreservesTheOriginalRegion() {
    let source: [UInt8] = [10, 10, 10, 255,  20, 20, 20, 255]
    let padded = CoreMLUpscaler.reflectPad(source, width: 2, height: 1, bytesPerRow: 8, to: 4)
    #expect(padded[0] == 10)
    #expect(padded[4] == 20)
}

@Test func modelLoadsFromTheBundle() throws {
    let upscaler = try CoreMLUpscaler()
    #expect(upscaler.scale == 4)
}

@Test func upscalingAFullTileQuadruplesItsDimensions() throws {
    let upscaler = try CoreMLUpscaler()
    let tile = [UInt8](repeating: 128, count: 256 * 256 * 4)
    let result = try tile.withUnsafeBytes { raw in
        try upscaler.upscale(tile: raw.baseAddress!, width: 256, height: 256, bytesPerRow: 256 * 4)
    }
    #expect(result.width == 1024)
    #expect(result.height == 1024)
    #expect(result.pixels.count == 1024 * 1024 * 4)
}

@Test func upscalingAPartialTileCropsBackToTheScaledSize() throws {
    let upscaler = try CoreMLUpscaler()
    let tile = [UInt8](repeating: 90, count: 100 * 60 * 4)
    let result = try tile.withUnsafeBytes { raw in
        try upscaler.upscale(tile: raw.baseAddress!, width: 100, height: 60, bytesPerRow: 100 * 4)
    }
    #expect(result.width == 400)
    #expect(result.height == 240)
}

@Test func aFlatGreyTileStaysFlatGrey() throws {
    // Sanity check that the conversion is not producing garbage: a uniform
    // input must produce a near-uniform output.
    let upscaler = try CoreMLUpscaler()
    let tile = [UInt8](repeating: 128, count: 256 * 256 * 4)
    let result = try tile.withUnsafeBytes { raw in
        try upscaler.upscale(tile: raw.baseAddress!, width: 256, height: 256, bytesPerRow: 256 * 4)
    }
    let samples = stride(from: 0, to: result.pixels.count, by: 4096).map { Int(result.pixels[$0]) }
    #expect(samples.allSatisfy { abs($0 - 128) < 12 }, "flat input produced \(samples.prefix(8))")
}

@Test func outputIsFullyOpaque() throws {
    // The model has no alpha channel; AlphaChannel reapplies it later.
    let upscaler = try CoreMLUpscaler()
    let tile = [UInt8](repeating: 100, count: 64 * 64 * 4)
    let result = try tile.withUnsafeBytes { raw in
        try upscaler.upscale(tile: raw.baseAddress!, width: 64, height: 64, bytesPerRow: 64 * 4)
    }
    #expect(result.pixels[3] == 255)
    #expect(result.pixels[result.pixels.count - 1] == 255)
}
