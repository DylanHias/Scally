import Testing
import Foundation
import CoreML
@testable import ScallyKit

/// Runs every bundled model on one realistically degraded fixture and writes
/// the outputs to disk, so the pixels can be judged directly rather than
/// through a SwiftUI image view.
@Test func writeModelBakeoff() async throws {
    let out = URL(filePath: "/tmp/claude-501/-Users-dylanhias-Scally/ebfc61c0-91bd-4f83-af92-678e732aa648/scratchpad")

    // 160px, photographic: soft gradients, a hard edge, and fine texture.
    let edge = 160
    var pixels = [UInt8](repeating: 255, count: edge * edge * 4)
    for y in 0..<edge {
        for x in 0..<edge {
            let i = (y * edge + x) * 4
            let fx = Double(x) / Double(edge), fy = Double(y) / Double(edge)
            var v = 0.45 + 0.25 * sin(fx * 9) * cos(fy * 7)
            if fx > 0.55 && fy > 0.25 && fy < 0.75 { v = 0.12 }           // hard edge
            if (x / 3) % 2 == 0 && fy > 0.80 { v *= 0.55 }                 // fine texture
            pixels[i] = UInt8(max(0, min(255, v * 255)))
            pixels[i+1] = UInt8(max(0, min(255, v * 236)))
            pixels[i+2] = UInt8(max(0, min(255, v * 208)))
        }
    }
    let buffer = try MappedPixelBuffer(width: edge, height: edge,
                                       directory: FileManager.default.temporaryDirectory)
    pixels.withUnsafeBytes { buffer.baseAddress.copyMemory(from: $0.baseAddress!, byteCount: pixels.count) }
    let source = out.appending(path: "bake-src.png")
    try? FileManager.default.removeItem(at: source)
    try OutputWriter.write(buffer: buffer, to: source, format: .png)

    for option in UpscalerOption.all {
        let started = Date()
        do {
            let pipeline = UpscalePipeline(upscaler: try option.makeUpscaler(computeUnits: .cpuAndGPU),
                                           faceRestorer: NoopFaceRestorer(),
                                           budget: MemoryBudget(availableBytes: 3_000_000_000))
            let r = try await pipeline.run(source: source, requestedScale: 4) { _ in }
            let dst = out.appending(path: "bake-\(option.id).png")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: r.outputURL, to: dst)
            print("BAKE \(option.id): \(r.outputWidth)px in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        } catch {
            print("BAKE \(option.id): FAILED \(error)")
        }
    }
}
