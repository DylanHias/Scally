import Testing
import Foundation
import CoreML
@testable import ScallyKit

/// Does post-sharpening visibly help? Writes the same upscale at several
/// intensities so the trade-off against halos can be judged directly.
@Test func writeSharpenLadder() async throws {
    let out = URL(filePath: "/tmp/claude-501/-Users-dylanhias-Scally/ebfc61c0-91bd-4f83-af92-678e732aa648/scratchpad")
    let src = out.appending(path: "bake-src.png")
    guard FileManager.default.fileExists(atPath: src.path) else { return }

    for intensity in [0.0, 0.45, 0.9] {
        let pipeline = UpscalePipeline(
            upscaler: try CoreMLUpscaler(modelName: "NomosWebPhoto", computeUnits: .cpuAndGPU),
            faceRestorer: NoopFaceRestorer(),
            budget: MemoryBudget(availableBytes: 3_000_000_000),
            sharpener: Sharpener(intensity: intensity, radius: 1.6))
        let r = try await pipeline.run(source: src, requestedScale: 4) { _ in }
        let dst = out.appending(path: "sharp-\(Int(intensity * 100)).png")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: r.outputURL, to: dst)
        print("SHARPEN \(intensity) -> \(r.outputWidth)px")
    }
}
