import Testing
import Foundation
@testable import ScallyKit

/// Thread-safe sink for the progress callback, which is @Sendable.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func record(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
    var samples: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

private func writeFixture(width: Int, height: Int) throws -> URL {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i] = UInt8((x * 5) % 256)
            pixels[i + 1] = 120
            pixels[i + 2] = UInt8((y * 3) % 256)
            pixels[i + 3] = 255
        }
    }
    let buffer = try MappedPixelBuffer(width: width, height: height,
                                       directory: FileManager.default.temporaryDirectory)
    pixels.withUnsafeBytes { raw in
        buffer.baseAddress.copyMemory(from: raw.baseAddress!, byteCount: pixels.count)
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("fixture-\(UUID().uuidString).png")
    try OutputWriter.write(buffer: buffer, to: url, format: .png)
    return url
}

private func makePipeline() throws -> UpscalePipeline {
    UpscalePipeline(upscaler: try CoreMLUpscaler(), faceRestorer: NoopFaceRestorer())
}

@Test func pipelineProducesAnOutputFourTimesLarger() async throws {
    let source = try writeFixture(width: 120, height: 80)
    let result = try await makePipeline().run(source: source, requestedScale: 4) { _ in }

    #expect(result.outputWidth == 480)
    #expect(result.outputHeight == 320)
    #expect(result.appliedScale == 4)
    #expect(FileManager.default.fileExists(atPath: result.outputURL.path))
    try? FileManager.default.removeItem(at: result.outputURL)
}

@Test func progressIsMonotonicAndReachesOne() async throws {
    let source = try writeFixture(width: 300, height: 200)
    let log = ProgressLog()
    _ = try await makePipeline().run(source: source, requestedScale: 4) { log.record($0) }

    let samples = log.samples
    #expect(samples.count > 1)
    #expect(samples == samples.sorted(), "progress must be monotonic, got \(samples)")
    #expect(samples.last! >= 0.999)
}

@Test func requestingTwoTimesDownsamplesTheFourTimesResult() async throws {
    let source = try writeFixture(width: 100, height: 100)
    let result = try await makePipeline().run(source: source, requestedScale: 2) { _ in }

    #expect(result.outputWidth == 200)
    #expect(result.outputHeight == 200)
    #expect(result.appliedScale == 2)
    try? FileManager.default.removeItem(at: result.outputURL)
}

@Test func cancellationStopsTheRunAndLeavesNoScratchFiles() async throws {
    // A private scratch directory: the shared temp dir is unusable for this
    // assertion because Swift Testing runs these tests in parallel.
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("scratch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let source = try writeFixture(width: 900, height: 700)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(),
                                   faceRestorer: NoopFaceRestorer(),
                                   scratchDirectory: scratch)

    let task = Task { try await pipeline.run(source: source, requestedScale: 4) { _ in } }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }

    let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
    #expect(leftovers.isEmpty, "scratch files leaked: \(leftovers)")
}

@Test func aCompletedRunAlsoLeavesNoScratchFiles() async throws {
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("scratch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let source = try writeFixture(width: 200, height: 150)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(),
                                   faceRestorer: NoopFaceRestorer(),
                                   scratchDirectory: scratch)
    let result = try await pipeline.run(source: source, requestedScale: 2,
                                        destinationDirectory: FileManager.default.temporaryDirectory) { _ in }

    let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
    #expect(leftovers.isEmpty, "scratch survived a successful run: \(leftovers)")
    try? FileManager.default.removeItem(at: result.outputURL)
}

@Test func aTightBudgetClampsTheAppliedScale() async throws {
    let source = try writeFixture(width: 400, height: 400)
    // 400x400 at 4x is 10.2MB; the 0.6 safety factor makes 12MB allow 2x only.
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(),
                                   faceRestorer: NoopFaceRestorer(),
                                   budget: MemoryBudget(availableBytes: 5_000_000))
    let result = try await pipeline.run(source: source, requestedScale: 4) { _ in }

    #expect(result.appliedScale == 2)
    #expect(result.wasClamped)
    #expect(result.outputWidth == 800)
    try? FileManager.default.removeItem(at: result.outputURL)
}

@Test func anImpossibleBudgetThrowsRatherThanRunning() async throws {
    let source = try writeFixture(width: 400, height: 400)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(),
                                   faceRestorer: NoopFaceRestorer(),
                                   budget: MemoryBudget(availableBytes: 1000))
    await #expect(throws: UpscaleError.self) {
        _ = try await pipeline.run(source: source, requestedScale: 4) { _ in }
    }
}

@Test func transparencySurvivesTheWholePipeline() async throws {
    // A PNG with a transparent corner must come out transparent and as a PNG.
    let width = 64, height = 64
    var pixels = [UInt8](repeating: 200, count: width * height * 4)
    for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
    for y in 0..<16 { for x in 0..<16 { pixels[(y * width + x) * 4 + 3] = 0 } }

    let buffer = try MappedPixelBuffer(width: width, height: height,
                                       directory: FileManager.default.temporaryDirectory)
    pixels.withUnsafeBytes { raw in
        buffer.baseAddress.copyMemory(from: raw.baseAddress!, byteCount: pixels.count)
    }
    let source = FileManager.default.temporaryDirectory
        .appendingPathComponent("alpha-\(UUID().uuidString).png")
    try OutputWriter.write(buffer: buffer, to: source, format: .png)

    let result = try await makePipeline().run(source: source, requestedScale: 4) { _ in }
    #expect(result.outputURL.pathExtension == "png", "alpha input must produce PNG")

    let reloaded = try ImageLoader.load(url: result.outputURL)
    #expect(reloaded.pixels[3] < 64, "the transparent corner must survive")
    try? FileManager.default.removeItem(at: result.outputURL)
}
