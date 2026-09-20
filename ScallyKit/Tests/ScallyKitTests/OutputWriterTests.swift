import Testing
import Foundation
import ImageIO
@testable import ScallyKit

private func filledBuffer(_ width: Int, _ height: Int, value: UInt8) throws -> MappedPixelBuffer {
    let buffer = try MappedPixelBuffer(width: width, height: height,
                                       directory: FileManager.default.temporaryDirectory)
    let pixels = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    for index in 0..<(width * height * 4) { pixels[index] = value }
    return buffer
}

@Test func writesAPNGThatReloadsAtTheSameSize() throws {
    let buffer = try filledBuffer(32, 16, value: 180)
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("out-\(UUID().uuidString).png")
    try OutputWriter.write(buffer: buffer, to: destination, format: .png)

    let source = CGImageSourceCreateWithURL(destination as CFURL, nil)!
    let reloaded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    #expect(reloaded.width == 32)
    #expect(reloaded.height == 16)

    try? FileManager.default.removeItem(at: destination)
}

@Test func writesHEICForOpaqueOutput() throws {
    let buffer = try filledBuffer(16, 16, value: 90)
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("out-\(UUID().uuidString).heic")
    try OutputWriter.write(buffer: buffer, to: destination, format: .heic(quality: 0.9))

    #expect(FileManager.default.fileExists(atPath: destination.path))
    let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as! Int
    #expect(size > 0)

    try? FileManager.default.removeItem(at: destination)
}

@Test func formatSelectionFollowsAlphaPresence() {
    #expect(OutputWriter.Format.preferred(hasAlpha: true).isPNG)
    #expect(OutputWriter.Format.preferred(hasAlpha: false).isPNG == false)
}

@Test func formatCarriesTheMatchingFileExtension() {
    #expect(OutputWriter.Format.png.fileExtension == "png")
    #expect(OutputWriter.Format.heic(quality: 0.9).fileExtension == "heic")
}

@Test func writingToAnUnwritablePathThrows() throws {
    let buffer = try filledBuffer(8, 8, value: 10)
    let bad = URL(fileURLWithPath: "/definitely/not/a/directory/out.png")
    #expect(throws: UpscaleError.encodingFailed) {
        try OutputWriter.write(buffer: buffer, to: bad, format: .png)
    }
}

@Test func pixelValuesSurviveTheRoundTrip() throws {
    let buffer = try filledBuffer(8, 8, value: 200)
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("rt-\(UUID().uuidString).png")
    try OutputWriter.write(buffer: buffer, to: destination, format: .png)

    let reloaded = try ImageLoader.load(url: destination)
    #expect(reloaded.width == 8 && reloaded.height == 8)
    #expect(reloaded.pixels[0] == 200, "PNG must be lossless, got \(reloaded.pixels[0])")

    try? FileManager.default.removeItem(at: destination)
}
