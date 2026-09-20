import Testing
import Foundation
import SwiftData
@testable import Scally
@testable import ScallyKit

private func makeContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: UpscaleRecord.self, configurations: configuration)
    return ModelContext(container)
}

private func makeTempRoot() -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Produces a (sourceURL, result) pair standing in for a finished upscale.
private func stagedUpscale(in root: URL, outputBytes: Int = 3000) throws -> (source: URL, result: UpscaleResult) {
    let source = root.appending(path: "IMG_4471.JPG")
    try Data(repeating: 1, count: 500).write(to: source)
    let produced = root.appending(path: "produced-\(UUID().uuidString).heic")
    try Data(repeating: 2, count: outputBytes).write(to: produced)
    let result = UpscaleResult(outputURL: produced, outputWidth: 960, outputHeight: 960,
                               appliedScale: 4, requestedScale: 4, duration: 6.0)
    return (source, result)
}

@Test func savingMovesTheOutputAndRetainsTheInput() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()
    let staged = try stagedUpscale(in: root)

    let record = try store.save(result: staged.result, sourceURL: staged.source,
                                originalFilename: "IMG_4471.JPG",
                                inputWidth: 240, inputHeight: 240,
                                thumbnail: Data([9, 9]), context: context)

    #expect(FileManager.default.fileExists(atPath: store.outputURL(for: record).path))
    #expect(FileManager.default.fileExists(atPath: store.inputURL(for: record).path),
            "the original must be retained for press-and-hold")
    #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: record).path))
    #expect(record.outputWidth == 960)
    #expect(record.inputWidth == 240)
}

@Test func theSourceFileIsCopiedNotConsumed() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()
    let staged = try stagedUpscale(in: root)

    _ = try store.save(result: staged.result, sourceURL: staged.source,
                       originalFilename: "IMG_4471.JPG", inputWidth: 240, inputHeight: 240,
                       thumbnail: Data([9]), context: context)

    #expect(FileManager.default.fileExists(atPath: staged.source.path),
            "the caller's source must survive - the retry path needs it")
}

@Test func dimensionSummaryMatchesTheDesign() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()
    let staged = try stagedUpscale(in: root)

    let record = try store.save(result: staged.result, sourceURL: staged.source,
                                originalFilename: "IMG_4471.JPG", inputWidth: 240, inputHeight: 240,
                                thumbnail: Data([9]), context: context)

    #expect(record.dimensionSummary == "240x240 -> 960x960")
}

@Test func deletingRemovesAllThreeFilesAndTheRecord() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()
    let staged = try stagedUpscale(in: root)

    let record = try store.save(result: staged.result, sourceURL: staged.source,
                                originalFilename: "IMG_4471.JPG", inputWidth: 240, inputHeight: 240,
                                thumbnail: Data([9]), context: context)

    let paths = [store.outputURL(for: record).path,
                 store.inputURL(for: record).path,
                 store.thumbnailURL(for: record).path]
    try store.delete(record, context: context)

    for path in paths {
        #expect(FileManager.default.fileExists(atPath: path) == false, "leaked \(path)")
    }
    #expect(try context.fetch(FetchDescriptor<UpscaleRecord>()).isEmpty)
}

@Test func batchDeleteRemovesEverySelectedRecord() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()

    var records: [UpscaleRecord] = []
    for index in 0..<3 {
        let staged = try stagedUpscale(in: root)
        records.append(try store.save(result: staged.result, sourceURL: staged.source,
                                      originalFilename: "IMG_\(index).JPG",
                                      inputWidth: 240, inputHeight: 240,
                                      thumbnail: Data([9]), context: context))
    }
    try store.delete(records, context: context)
    #expect(try context.fetch(FetchDescriptor<UpscaleRecord>()).isEmpty)
}

@Test func outputsAndInputsAreExcludedFromBackup() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()
    let staged = try stagedUpscale(in: root)

    let record = try store.save(result: staged.result, sourceURL: staged.source,
                                originalFilename: "IMG_4471.JPG", inputWidth: 240, inputHeight: 240,
                                thumbnail: Data([9]), context: context)

    for url in [store.outputURL(for: record), store.inputURL(for: record)] {
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true, "\(url.lastPathComponent) is backed up")
    }
}

@Test func totalBytesSumsStoredFiles() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()
    let staged = try stagedUpscale(in: root, outputBytes: 4000)

    _ = try store.save(result: staged.result, sourceURL: staged.source,
                       originalFilename: "IMG_4471.JPG", inputWidth: 240, inputHeight: 240,
                       thumbnail: Data(repeating: 1, count: 50), context: context)

    // Output 4000 + retained input 500 + thumbnail 50, plus the staging files
    // that happen to share this root.
    #expect(store.totalBytes() >= 4550)
}

@Test func clearingRemovesEverything() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()
    for index in 0..<4 {
        let staged = try stagedUpscale(in: root)
        _ = try store.save(result: staged.result, sourceURL: staged.source,
                           originalFilename: "IMG_\(index).JPG",
                           inputWidth: 240, inputHeight: 240,
                           thumbnail: Data([9]), context: context)
    }
    try store.deleteAll(context: context)
    #expect(try context.fetch(FetchDescriptor<UpscaleRecord>()).isEmpty)
}
