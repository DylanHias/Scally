import Testing
import Foundation
@testable import ScallyKit

/// A structured, sharp image: a smooth background with hard-edged shapes on
/// it. Sharp edges and flat regions, which is what a clean photograph looks
/// like to these measures.
private func cleanImage(width: Int = 192, height: Int = 192) -> LoadedImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            // Every period here is deliberately coprime with 8. An earlier
            // version used 24, a multiple of it, so every edge in the "clean"
            // fixture landed exactly on the JPEG block grid and it measured a
            // blockiness of 19.7 - the fixture was pathological, not the
            // detector.
            // Cells are large and their periods coprime with 8, so the
            // measurement blocks mostly fall *inside* a cell: hard edges for
            // `sharpness`, genuinely smooth interiors for the noise floor. An
            // earlier version added fine diagonal stripes, which put high
            // frequency in every block and made a clean fixture read as noise
            // at 17.6.
            var value = 40.0 + 120.0 * Double(x) / Double(width)
            if ((x / 47) + (y / 41)) % 2 == 0 { value += 55 }
            if x > 37 && x < 91 && y > 43 && y < 97 { value = 230 }
            let p = (y * width + x) * 4
            let byte = UInt8(max(0, min(255, value)))
            pixels[p] = byte; pixels[p + 1] = byte; pixels[p + 2] = byte
        }
    }
    return LoadedImage(pixels: pixels, width: width, height: height, hasAlpha: false)
}

private func mapped(_ image: LoadedImage,
                    _ transform: (Int, Int, [UInt8]) -> Double) -> LoadedImage {
    var pixels = image.pixels
    for y in 0..<image.height {
        for x in 0..<image.width {
            let value = UInt8(max(0, min(255, transform(x, y, image.pixels))))
            let p = (y * image.width + x) * 4
            pixels[p] = value; pixels[p + 1] = value; pixels[p + 2] = value
        }
    }
    return LoadedImage(pixels: pixels, width: image.width, height: image.height,
                       hasAlpha: false)
}

@Test func aCleanImageIsResampledRatherThanModelled() {
    let quality = InputQuality.measure(cleanImage())
    #expect(!quality.needsRestoration,
            "clean: blockiness \(quality.blockiness), sharpness \(quality.sharpness), noise \(quality.noise)")
    #expect(quality.reason == "already clean")
}

@Test func aBlurredImageAsksForTheModel() {
    let source = cleanImage()
    let width = source.width, height = source.height
    // A 5-tap box blur: enough to strip high frequencies while leaving the
    // mid-frequency structure, which is exactly what `sharpness` detects.
    let blurred = mapped(source) { x, y, pixels in
        var total = 0.0, count = 0.0
        for dy in -2...2 {
            for dx in -2...2 {
                let sx = min(max(x + dx, 0), width - 1)
                let sy = min(max(y + dy, 0), height - 1)
                total += Double(pixels[(sy * width + sx) * 4]); count += 1
            }
        }
        return total / count
    }
    let quality = InputQuality.measure(blurred)
    #expect(quality.needsRestoration,
            "blurred: sharpness \(quality.sharpness) should be under 0.70")
    #expect(quality.sharpness < InputQuality.measure(source).sharpness)
}

@Test func aNoisyImageAsksForTheModel() {
    var seed: UInt64 = 0x9E3779B97F4A7C15
    let noisy = mapped(cleanImage()) { x, y, pixels in
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let jitter = Double(Int(truncatingIfNeeded: seed >> 33) % 41) - 20
        return Double(pixels[(y * 192 + x) * 4]) + jitter
    }
    let quality = InputQuality.measure(noisy)
    #expect(quality.needsRestoration,
            "noisy: noise \(quality.noise) should exceed 4.0")
    #expect(quality.reason == "sensor noise" || quality.reason == "soft detail")
}

@Test func compressionArtefactsAskForTheModel() {
    // A per-block brightness step, which is what DC quantisation produces and
    // what `blockiness` exists to see. Deliberately *not* flattening each
    // block: that leaves no variation inside one, the ratio's denominator
    // collapses, and the measure degenerates to 1.0 - which is how the first
    // version of this test managed to fail against a correct detector.
    let blocky = mapped(cleanImage()) { x, y, pixels in
        let step = Double(((x / 8) &* 7 &+ (y / 8) &* 13) % 5) * 9 - 18
        return Double(pixels[(y * 192 + x) * 4]) + step
    }
    let quality = InputQuality.measure(blocky)
    #expect(quality.blockiness > 1.8, "blockiness was \(quality.blockiness)")
    #expect(quality.needsRestoration)
}

@Test func anImageTooSmallToMeasureIsSentToTheModel() {
    let tiny = LoadedImage(pixels: [UInt8](repeating: 128, count: 8 * 8 * 4),
                           width: 8, height: 8, hasAlpha: false)
    #expect(InputQuality.measure(tiny).needsRestoration)
}
