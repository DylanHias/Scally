import Testing
import Foundation
@testable import ScallyKit

private func solidTile(width: Int, height: Int, value: UInt8) -> [UInt8] {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = value; pixels[index + 1] = value; pixels[index + 2] = value
    }
    return pixels
}

private func tempBuffer(_ width: Int, _ height: Int) throws -> MappedPixelBuffer {
    try MappedPixelBuffer(width: width, height: height,
                          directory: FileManager.default.temporaryDirectory)
}

@Test func writingASingleTileCopiesItVerbatim() throws {
    let buffer = try tempBuffer(8, 8)
    let composer = TileComposer(buffer: buffer, overlap: 4)
    var tile = solidTile(width: 8, height: 8, value: 120)

    tile.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 8, height: 8),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }

    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    #expect(out[0] == 120)
    #expect(out[(7 * 8 + 7) * 4] == 120)
}

@Test func identicalOverlappingTilesLeaveNoSeam() throws {
    // Two tiles of the same value must blend to exactly that value everywhere,
    // whatever the ramp does. This is what makes the reconstruction test exact.
    let buffer = try tempBuffer(12, 4)
    let composer = TileComposer(buffer: buffer, overlap: 4)

    var left = solidTile(width: 8, height: 4, value: 90)
    left.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 8, height: 4),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }
    var right = solidTile(width: 8, height: 4, value: 90)
    right.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 4, y: 0, width: 8, height: 4),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }

    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    for x in 0..<12 {
        #expect(out[x * 4] == 90, "seam at column \(x)")
    }
}

@Test func overlapBlendIsMonotonicBetweenDifferingTiles() throws {
    let buffer = try tempBuffer(12, 1)
    let composer = TileComposer(buffer: buffer, overlap: 4)

    var left = solidTile(width: 8, height: 1, value: 0)
    left.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 8, height: 1),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }
    var right = solidTile(width: 8, height: 1, value: 255)
    right.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 4, y: 0, width: 8, height: 1),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }

    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    let band = (4..<8).map { Int(out[$0 * 4]) }
    #expect(band == band.sorted(), "blend must ramp monotonically, got \(band)")
    #expect(band.first! < band.last!)
}

@Test func verticalOverlapAlsoBlends() throws {
    // The vertical ramp is a separate code path from the horizontal one.
    let buffer = try tempBuffer(4, 12)
    let composer = TileComposer(buffer: buffer, overlap: 4)

    var top = solidTile(width: 4, height: 8, value: 0)
    top.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 4, height: 8),
                       pixels: raw.baseAddress!, bytesPerRow: 16)
    }
    var bottom = solidTile(width: 4, height: 8, value: 255)
    bottom.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 4, width: 4, height: 8),
                       pixels: raw.baseAddress!, bytesPerRow: 16)
    }

    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    let band = (4..<8).map { Int(out[$0 * buffer.bytesPerRow]) }
    #expect(band == band.sorted(), "vertical blend must ramp, got \(band)")
    #expect(band.first! < band.last!)
}

@Test func writesAreClippedToTheBuffer() throws {
    // A tile that runs past the edge must not corrupt memory or crash.
    let buffer = try tempBuffer(6, 6)
    let composer = TileComposer(buffer: buffer, overlap: 2)
    var tile = solidTile(width: 8, height: 8, value: 200)
    tile.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 8, height: 8),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }
    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    #expect(out[(5 * 6 + 5) * 4] == 200)
}
