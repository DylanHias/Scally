import Testing
import Foundation
import CoreML
@testable import ScallyKit

/// Writes a real end-to-end comparison so the result can be inspected by eye.
/// Not an assertion of quality - quality is a judgement, and this is the file
/// that lets a human make it.
@Test func writeDiffusionComparison() async throws {
    let out = URL(filePath: "/tmp/claude-501/-Users-dylanhias-Scally/ebfc61c0-91bd-4f83-af92-678e732aa648/scratchpad")

    // A deliberately degraded 120x120 source - the app's actual target input.
    let edge = 120
    var pixels = [UInt8](repeating: 255, count: edge * edge * 4)
    for y in 0..<edge {
        for x in 0..<edge {
            let i = (y * edge + x) * 4
            let bar = (x / 9) % 2 == 0 && (y % 26) < 15
            let wave = 0.5 + 0.28 * sin(Double(x) / 6) * cos(Double(y) / 9)
            let v = bar ? 0.12 : wave
            pixels[i] = UInt8(max(0, min(255, v * 255)))
            pixels[i + 1] = UInt8(max(0, min(255, v * 240)))
            pixels[i + 2] = UInt8(max(0, min(255, v * 215)))
        }
    }
    let buffer = try MappedPixelBuffer(width: edge, height: edge,
                                       directory: FileManager.default.temporaryDirectory)
    pixels.withUnsafeBytes { buffer.baseAddress.copyMemory(from: $0.baseAddress!, byteCount: pixels.count) }
    let source = out.appending(path: "swift-src.png")
    try? FileManager.default.removeItem(at: source)
    try OutputWriter.write(buffer: buffer, to: source, format: .png)

    let started = Date()
    let pipeline = UpscalePipeline(upscaler: try ResShiftUpscaler(computeUnits: .cpuAndGPU),
                                   faceRestorer: NoopFaceRestorer(),
                                   budget: MemoryBudget(availableBytes: 3_000_000_000))
    let result = try await pipeline.run(source: source, requestedScale: 4) { _ in }
    let elapsed = Date().timeIntervalSince(started)

    let destination = out.appending(path: "swift-diffusion.png")
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: result.outputURL, to: destination)

    print("DIFFUSION \(edge)x\(edge) -> \(result.outputWidth)x\(result.outputHeight) in \(String(format: "%.1f", elapsed))s")
    #expect(result.outputWidth == edge * 4)
}
