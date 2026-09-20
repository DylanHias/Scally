import Testing
import Foundation
@testable import ScallyKit

/// Deterministic noise: every pixel distinct enough that a seam, an off-by-one,
/// or a dropped tile shows up as an exact byte mismatch.
private func makeSource(width: Int, height: Int) -> [UInt8] {
    var source = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            source[i] = UInt8((x * 7 + y * 13) % 256)
            source[i + 1] = UInt8((x * 3 + y * 29) % 256)
            source[i + 2] = UInt8((x &* y) % 256)
            source[i + 3] = 255
        }
    }
    return source
}

private func reconstruct(width: Int, height: Int, tileSize: Int, overlap: Int) throws -> (source: [UInt8], mismatches: Int) {
    let source = makeSource(width: width, height: height)
    let buffer = try MappedPixelBuffer(width: width, height: height,
                                       directory: FileManager.default.temporaryDirectory)
    let composer = TileComposer(buffer: buffer, overlap: overlap)
    let grid = TileGrid(imageWidth: width, imageHeight: height, tileSize: tileSize, overlap: overlap)
    let upscaler = IdentityUpscaler()

    for tile in grid.tiles {
        var tilePixels = [UInt8](repeating: 0, count: tile.width * tile.height * 4)
        for row in 0..<tile.height {
            let sourceStart = ((tile.y + row) * width + tile.x) * 4
            let destinationStart = row * tile.width * 4
            for byte in 0..<(tile.width * 4) {
                tilePixels[destinationStart + byte] = source[sourceStart + byte]
            }
        }
        let result = try tilePixels.withUnsafeBytes { raw in
            try upscaler.upscale(tile: raw.baseAddress!, width: tile.width,
                                 height: tile.height, bytesPerRow: tile.width * 4)
        }
        result.pixels.withUnsafeBytes { raw in
            composer.write(tile: tile, pixels: raw.baseAddress!, bytesPerRow: result.bytesPerRow)
        }
    }

    let output = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    var mismatches = 0
    for index in 0..<(width * height * 4) where output[index] != source[index] {
        mismatches += 1
    }
    return (source, mismatches)
}

@Test func identityUpscalerReconstructsTheSourceExactly() throws {
    let (_, mismatches) = try reconstruct(width: 700, height: 500, tileSize: 256, overlap: 16)
    #expect(mismatches == 0, "\(mismatches) bytes differ after tiled reconstruction")
}

@Test(arguments: [
    (w: 100, h: 80),      // smaller than one tile
    (w: 256, h: 256),     // exactly one tile
    (w: 257, h: 257),     // one pixel past a tile
    (w: 1000, h: 13),     // extreme aspect ratio
    (w: 13, h: 1000),
])
func reconstructionIsExactAcrossAwkwardSizes(size: (w: Int, h: Int)) throws {
    let (_, mismatches) = try reconstruct(width: size.w, height: size.h, tileSize: 256, overlap: 16)
    #expect(mismatches == 0, "\(size.w)x\(size.h): \(mismatches) bytes differ")
}

@Test func noopFaceRestorerReportsItChangedNothing() throws {
    let restorer = NoopFaceRestorer()
    var pixels: [UInt8] = [1, 2, 3, 255, 4, 5, 6, 255]
    let before = pixels
    let result = try pixels.withUnsafeMutableBytes { raw in
        try restorer.restore(image: raw.baseAddress!, width: 2, height: 1, bytesPerRow: 8)
    }
    #expect(result == false, "v1 must report that it changed nothing")
    #expect(pixels == before, "and must actually change nothing")
}
