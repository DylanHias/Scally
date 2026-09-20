import Testing
import Foundation
@testable import ScallyKit

@Test func extractPullsTheFourthByteOfEveryPixel() {
    let pixels: [UInt8] = [10, 20, 30, 40,   50, 60, 70, 80]
    let alpha = AlphaChannel.extract(from: pixels, width: 2, height: 1, bytesPerRow: 8)
    #expect(alpha == [40, 80])
}

@Test func scalingEnlargesTheAlphaPlane() {
    let alpha: [UInt8] = [0, 255, 255, 0]
    let scaled = AlphaChannel.scaled(alpha, from: (width: 2, height: 2), to: (width: 4, height: 4))
    #expect(scaled.count == 16)
}

@Test func applyWritesAlphaBackIntoRGBA() {
    var pixels: [UInt8] = [1, 2, 3, 255,   4, 5, 6, 255]
    AlphaChannel.apply([0, 128], to: &pixels, width: 2, height: 1, bytesPerRow: 8)
    #expect(pixels[3] == 0)
    #expect(pixels[7] == 128)
    #expect(pixels[0] == 1, "colour channels must be untouched")
    #expect(pixels[4] == 4)
}

@Test func roundTripPreservesATransparentCorner() {
    let pixels: [UInt8] = [9, 9, 9, 0,    9, 9, 9, 255,
                           9, 9, 9, 255,  9, 9, 9, 255]
    let alpha = AlphaChannel.extract(from: pixels, width: 2, height: 2, bytesPerRow: 8)
    let scaled = AlphaChannel.scaled(alpha, from: (2, 2), to: (8, 8))
    var output = [UInt8](repeating: 255, count: 8 * 8 * 4)
    AlphaChannel.apply(scaled, to: &output, width: 8, height: 8, bytesPerRow: 32)
    #expect(output[3] < 64, "the transparent corner must still be transparent")
}

@Test func fullyOpaquePlanesStayOpaqueThroughScaling() {
    let alpha = [UInt8](repeating: 255, count: 16)
    let scaled = AlphaChannel.scaled(alpha, from: (4, 4), to: (16, 16))
    #expect(scaled.allSatisfy { $0 == 255 }, "scaling must not introduce transparency")
}

@Test func extractHandlesPaddedRows() {
    // bytesPerRow larger than width*4 is legal and must not misread.
    let width = 2, height = 2, stride = 12
    var pixels = [UInt8](repeating: 0, count: stride * height)
    pixels[3] = 11; pixels[7] = 22
    pixels[stride + 3] = 33; pixels[stride + 7] = 44
    let alpha = AlphaChannel.extract(from: pixels, width: width, height: height, bytesPerRow: stride)
    #expect(alpha == [11, 22, 33, 44])
}
