import Testing
import Foundation
import CoreML
@testable import ScallyKit

/// Deterministic pseudo-random source so fixtures are byte-identical on every
/// machine. `SystemRandomNumberGenerator` would make golden tests meaningless.
private struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func unit() -> Double { Double(next() % 10_000) / 10_000.0 }
}

private let fixturesDirectory = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Fixtures")

private let minimumPSNR = 35.0
private let fixtureSize = 96

/// Three synthetic but image-like fixtures. Generated in code rather than
/// committed as inputs: deterministic, no binary blobs, and no third-party
/// image licensing to worry about inside the test bundle.
/// Seed derived from the name's bytes, NOT from `hashValue`.
///
/// Swift seeds String hashing randomly per process, so `name.hashValue` differs
/// on every run. That made these "deterministic" fixtures different each time,
/// and the texture case - which uses the most generator output - failed against
/// its own freshly recorded reference.
private func seed(for name: String) -> UInt64 {
    var value: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a offset basis
    for byte in name.utf8 {
        value = (value ^ UInt64(byte)) &* 0x1000_0000_01b3
    }
    return value | 1
}

private func makeFixture(named name: String) -> [UInt8] {
    var generator = SeededGenerator(seed: seed(for: name))
    var pixels = [UInt8](repeating: 255, count: fixtureSize * fixtureSize * 4)

    for y in 0..<fixtureSize {
        for x in 0..<fixtureSize {
            let index = (y * fixtureSize + x) * 4
            let fx = Double(x) / Double(fixtureSize)
            let fy = Double(y) / Double(fixtureSize)
            var r = 0.0, g = 0.0, b = 0.0

            switch name {
            case "portrait":
                // Soft elliptical falloff plus gentle shading - face-like gradients.
                let dx = fx - 0.5, dy = fy - 0.45
                let falloff = max(0, 1 - (dx * dx * 4 + dy * dy * 3) * 2.2)
                r = 0.35 + 0.5 * falloff + 0.02 * generator.unit()
                g = 0.28 + 0.42 * falloff + 0.02 * generator.unit()
                b = 0.24 + 0.36 * falloff + 0.02 * generator.unit()
            case "text":
                // Hard-edged bars: the case where ringing and blur show up.
                let bar = (x / 6) % 2 == 0 && (y % 18) < 11
                let value = bar ? 0.08 : 0.94
                r = value; g = value; b = value
            default:
                // Fine texture with structure - foliage or fabric.
                let wave = 0.5 + 0.25 * sin(fx * 18) * cos(fy * 14)
                let grain = 0.12 * generator.unit()
                r = wave * 0.7 + grain
                g = wave * 0.85 + grain
                b = wave * 0.5 + grain
            }

            pixels[index] = UInt8(max(0, min(255, r * 255)))
            pixels[index + 1] = UInt8(max(0, min(255, g * 255)))
            pixels[index + 2] = UInt8(max(0, min(255, b * 255)))
            pixels[index + 3] = 255
        }
    }
    return pixels
}

private func writeFixtureImage(named name: String) throws -> URL {
    let pixels = makeFixture(named: name)
    let buffer = try MappedPixelBuffer(width: fixtureSize, height: fixtureSize,
                                       directory: FileManager.default.temporaryDirectory)
    pixels.withUnsafeBytes { raw in
        buffer.baseAddress.copyMemory(from: raw.baseAddress!, byteCount: pixels.count)
    }
    let url = FileManager.default.temporaryDirectory
        .appending(path: "golden-\(name)-\(UUID().uuidString).png")
    try OutputWriter.write(buffer: buffer, to: url, format: .png)
    return url
}

private func psnr(_ a: LoadedImage, _ b: LoadedImage) -> Double {
    guard a.width == b.width, a.height == b.height else { return 0 }
    var sumSquaredError = 0.0
    var counted = 0
    for index in 0..<a.pixels.count where index % 4 != 3 {
        let difference = Double(a.pixels[index]) - Double(b.pixels[index])
        sumSquaredError += difference * difference
        counted += 1
    }
    let meanSquaredError = sumSquaredError / Double(counted)
    guard meanSquaredError > 0 else { return .infinity }
    return 10 * log10(255 * 255 / meanSquaredError)
}

@Test(arguments: ["portrait", "text", "texture"])
func upscaleMatchesGoldenReference(name: String) async throws {
    let source = try writeFixtureImage(named: name)
    defer { try? FileManager.default.removeItem(at: source) }

    // CPU-only, deliberately: a regression gate must be reproducible, and .all
    // lets Core ML schedule across ANE, GPU and CPU as it sees fit. (That was
    // not what broke this test - see `seed(for:)` - but pinning it removes a
    // real source of variance for free, since the fixtures are one tile each.)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(computeUnits: .cpuOnly),
                                   faceRestorer: NoopFaceRestorer())
    let result = try await pipeline.run(source: source, requestedScale: 4) { _ in }
    defer { try? FileManager.default.removeItem(at: result.outputURL) }

    // The extension must follow the writer's actual choice. These fixtures are
    // opaque, so OutputWriter picks HEIC; hardcoding ".png" produced reference
    // files that were HEIC wearing the wrong suffix. ImageIO sniffs content and
    // loaded them anyway, so the mislabelling was invisible to the assertion.
    let reference = fixturesDirectory
        .appending(path: "\(name)-4x-reference.\(result.outputURL.pathExtension)")

    #expect(result.outputWidth == fixtureSize * 4)

    guard FileManager.default.fileExists(atPath: reference.path) else {
        try FileManager.default.createDirectory(at: fixturesDirectory,
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: result.outputURL, to: reference)
        Issue.record("recorded a new reference for \(name) - inspect it, commit it, re-run")
        return
    }

    let score = psnr(try ImageLoader.load(url: result.outputURL),
                     try ImageLoader.load(url: reference))
    #expect(score >= minimumPSNR,
            "\(name) regressed to \(String(format: "%.1f", score)) dB")
}
