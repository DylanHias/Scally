import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import ScallyKit

/// A 2x1 image: left pixel red, right pixel blue.
private func makeTwoPixelImage() -> CGImage {
    let bytes: [UInt8] = [255, 0, 0, 255,   0, 0, 255, 255]
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

@Test func upOrientationLeavesPixelsAlone() throws {
    let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: .up)
    #expect(loaded.width == 2 && loaded.height == 1)
    #expect(loaded.pixels[0] > 200, "left should be red")
    #expect(loaded.pixels[6] > 200, "right should be blue")
}

@Test func mirroredOrientationSwapsLeftAndRight() throws {
    let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: .upMirrored)
    #expect(loaded.pixels[2] > 200, "left pixel should now be blue")
    #expect(loaded.pixels[4] > 200, "right pixel should now be red")
}

@Test func rotatedOrientationsSwapTheAxes() throws {
    for orientation in [CGImagePropertyOrientation.left, .right, .leftMirrored, .rightMirrored] {
        let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: orientation)
        #expect(loaded.width == 1, "\(orientation) should produce a 1x2 image")
        #expect(loaded.height == 2)
    }
}

@Test func allEightOrientationsLoadWithConsistentBufferSize() throws {
    let all: [CGImagePropertyOrientation] = [.up, .upMirrored, .down, .downMirrored,
                                             .left, .leftMirrored, .right, .rightMirrored]
    for orientation in all {
        let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: orientation)
        #expect(loaded.pixels.count == loaded.width * loaded.height * 4)
        #expect(loaded.bytesPerRow == loaded.width * 4)
    }
}

@Test func opaqueImagesReportNoAlpha() throws {
    let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: .up)
    #expect(loaded.hasAlpha == false)
}

@Test func loadingFromDiskAppliesTheEmbeddedOrientation() throws {
    // Write a 2x1 image tagged .upMirrored, then confirm load() honours the tag.
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("orient-\(UUID().uuidString).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, makeTwoPixelImage(), [
        kCGImagePropertyOrientation: CGImagePropertyOrientation.upMirrored.rawValue
    ] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))

    let loaded = try ImageLoader.load(url: url)
    #expect(loaded.width == 2 && loaded.height == 1)
    #expect(loaded.pixels[2] > 200, "orientation tag should have mirrored the pixels")

    try? FileManager.default.removeItem(at: url)
}

@Test func unreadableFilesThrowRatherThanCrash() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope.png")
    #expect(throws: UpscaleError.unsupportedImageFormat) {
        _ = try ImageLoader.load(url: missing)
    }
}

@Test func genuinelyTransparentImagesReportAlpha() throws {
    // Same shape as the opaque fixture but with one transparent pixel.
    let bytes: [UInt8] = [255, 0, 0, 255,   0, 0, 0, 0]
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false,
                        intent: .defaultIntent)!

    let loaded = try ImageLoader.render(image, orientation: .up)
    #expect(loaded.hasAlpha, "a transparent pixel must be detected")
}
