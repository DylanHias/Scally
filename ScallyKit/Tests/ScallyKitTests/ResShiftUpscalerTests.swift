import Testing
import Foundation
import CoreML
@testable import ScallyKit

/// The diffusion path is stochastic, so these assert structural correctness and
/// that the output is a plausible image - not exact values.
@Test func resShiftReportsItsOwnTileGeometry() throws {
    let upscaler = try ResShiftUpscaler(computeUnits: .cpuAndGPU)
    #expect(upscaler.scale == 4)
    #expect(upscaler.inputTileSize == 64, "the UNet's attention masks are baked in at 64x64")
}

@Test func resShiftQuadruplesAFullTile() throws {
    let upscaler = try ResShiftUpscaler(computeUnits: .cpuAndGPU)
    var tile = [UInt8](repeating: 255, count: 64 * 64 * 4)
    for y in 0..<64 {
        for x in 0..<64 {
            let i = (y * 64 + x) * 4
            let v = UInt8((x / 4) % 2 == 0 ? 40 : 210)
            tile[i] = v; tile[i + 1] = v; tile[i + 2] = v
        }
    }
    let result = try tile.withUnsafeBytes {
        try upscaler.upscale(tile: $0.baseAddress!, width: 64, height: 64, bytesPerRow: 256)
    }
    #expect(result.width == 256)
    #expect(result.height == 256)
    #expect(result.pixels.count == 256 * 256 * 4)
    #expect(result.pixels[3] == 255, "alpha must be opaque")
}

@Test func resShiftOutputIsAnImageNotNoise() throws {
    // A vertical-bar pattern must survive as a vertical-bar pattern. If the
    // sampling constants or channel layout were wrong the output would be
    // plausible-looking noise, which is exactly the failure mode to catch.
    let upscaler = try ResShiftUpscaler(computeUnits: .cpuAndGPU)
    var tile = [UInt8](repeating: 255, count: 64 * 64 * 4)
    for y in 0..<64 {
        for x in 0..<64 {
            let i = (y * 64 + x) * 4
            let v = UInt8((x / 8) % 2 == 0 ? 30 : 220)
            tile[i] = v; tile[i + 1] = v; tile[i + 2] = v
        }
    }
    let result = try tile.withUnsafeBytes {
        try upscaler.upscale(tile: $0.baseAddress!, width: 64, height: 64, bytesPerRow: 256)
    }

    // Column means should still alternate dark/light with the bars.
    var columnMean = [Double](repeating: 0, count: 256)
    for x in 0..<256 {
        var total = 0.0
        for y in 0..<256 { total += Double(result.pixels[(y * 256 + x) * 4]) }
        columnMean[x] = total / 256
    }
    let darkBand = (0..<32).map { columnMean[$0] }.reduce(0, +) / 32
    let lightBand = (32..<64).map { columnMean[$0] }.reduce(0, +) / 32
    #expect(abs(lightBand - darkBand) > 40,
            "bars vanished: dark \(Int(darkBand)) vs light \(Int(lightBand))")

    let overall = columnMean.reduce(0, +) / 256
    #expect(overall > 20 && overall < 235, "output is saturated, mean \(Int(overall))")
}

@Test func resShiftHandlesAPartialEdgeTile() throws {
    let upscaler = try ResShiftUpscaler(computeUnits: .cpuAndGPU)
    let tile = [UInt8](repeating: 128, count: 40 * 25 * 4)
    let result = try tile.withUnsafeBytes {
        try upscaler.upscale(tile: $0.baseAddress!, width: 40, height: 25, bytesPerRow: 160)
    }
    #expect(result.width == 160)
    #expect(result.height == 100)
}
