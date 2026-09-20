import Testing
import Foundation
@testable import ScallyKit

@Test func bufferIsZeroFilledAndWritable() throws {
    let buffer = try MappedPixelBuffer(width: 64, height: 32,
                                       directory: FileManager.default.temporaryDirectory)
    let pixels = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)

    #expect(pixels[0] == 0)
    pixels[0] = 200
    #expect(pixels[0] == 200)
    #expect(buffer.bytesPerRow == 64 * 4)
}

@Test func bufferBackingFileIsRemovedOnDeinit() throws {
    var url: URL?
    do {
        let buffer = try MappedPixelBuffer(width: 16, height: 16,
                                           directory: FileManager.default.temporaryDirectory)
        url = buffer.fileURL
        #expect(FileManager.default.fileExists(atPath: buffer.fileURL.path))
    }
    #expect(FileManager.default.fileExists(atPath: url!.path) == false)
}

@Test func bufferProducesACGImageOfMatchingSize() throws {
    let buffer = try MappedPixelBuffer(width: 40, height: 20,
                                       directory: FileManager.default.temporaryDirectory)
    let image = try buffer.makeCGImage()
    #expect(image.width == 40)
    #expect(image.height == 20)
}

@Test func writesSurviveAcrossTheWholeMapping() throws {
    // The last byte is the one that proves ftruncate sized the file correctly.
    let width = 300, height = 200
    let buffer = try MappedPixelBuffer(width: width, height: height,
                                       directory: FileManager.default.temporaryDirectory)
    let pixels = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    let lastByte = width * height * 4 - 1
    pixels[lastByte] = 77
    #expect(pixels[lastByte] == 77)
}

@Test func largeAllocationDoesNotFail() throws {
    // 4000x3000 RGBA is 48MB - trivially fine as a mapping, fatal as a heap array.
    let buffer = try MappedPixelBuffer(width: 4000, height: 3000,
                                       directory: FileManager.default.temporaryDirectory)
    #expect(buffer.bytesPerRow == 16_000)
}
