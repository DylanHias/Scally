import Testing
import Foundation
import CoreML
@testable import ScallyKit

/// Single tile vs many tiles on the same content. If independent per-tile noise
/// is the problem, the multi-tile run will be visibly softer.
@Test func writeTileCoherenceComparison() async throws {
    let out = URL(filePath: "/tmp/claude-501/-Users-dylanhias-Scally/ebfc61c0-91bd-4f83-af92-678e732aa648/scratchpad")

    func fixture(_ edge: Int, to url: URL) throws {
        var pixels = [UInt8](repeating: 255, count: edge * edge * 4)
        for y in 0..<edge {
            for x in 0..<edge {
                let i = (y * edge + x) * 4
                let bar = (x / 5) % 2 == 0 && (y % 14) < 8
                let v = bar ? 0.10 : 0.5 + 0.3 * sin(Double(x) / 4) * cos(Double(y) / 6)
                pixels[i] = UInt8(max(0, min(255, v * 255)))
                pixels[i+1] = UInt8(max(0, min(255, v * 238)))
                pixels[i+2] = UInt8(max(0, min(255, v * 210)))
            }
        }
        let b = try MappedPixelBuffer(width: edge, height: edge,
                                      directory: FileManager.default.temporaryDirectory)
        pixels.withUnsafeBytes { b.baseAddress.copyMemory(from: $0.baseAddress!, byteCount: pixels.count) }
        try? FileManager.default.removeItem(at: url)
        try OutputWriter.write(buffer: b, to: url, format: .png)
    }

    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(modelName: "NomosWebPhoto", computeUnits: .cpuAndGPU),
                                   faceRestorer: NoopFaceRestorer(),
                                   budget: MemoryBudget(availableBytes: 3_000_000_000))

    // 64px = exactly one tile. 200px = a grid of them, same content scale.
    for (name, edge) in [("single", 64), ("multi", 200)] {
        let src = out.appending(path: "coh-src-\(name).png")
        try fixture(edge, to: src)
        let started = Date()
        let r = try await pipeline.run(source: src, requestedScale: 4) { _ in }
        let dst = out.appending(path: "coh-\(name).png")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: r.outputURL, to: dst)
        let tiles = TileGrid(imageWidth: edge, imageHeight: edge, tileSize: 64, overlap: 16).tiles.count
        print("COHERENCE \(name): \(edge)px -> \(r.outputWidth)px, \(tiles) tiles, \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    }
}
