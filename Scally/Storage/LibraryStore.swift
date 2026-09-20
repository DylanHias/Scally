import Foundation
import SwiftData
import ScallyKit

/// Owns the on-disk half of the library. SwiftData holds metadata; the images
/// live here.
///
/// Files go in Application Support, not Caches: the system may purge Caches,
/// and a history that silently empties itself is worse than no history. They
/// are excluded from iCloud backup because they are large and fully
/// regenerable (spec section 7).
struct LibraryStore {
    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
            self.root = support.appending(path: "Library", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func outputURL(for record: UpscaleRecord) -> URL {
        root.appending(path: "\(record.id.uuidString).\(record.outputExtension)")
    }

    /// The retained original, used by press-and-hold on the result screen.
    func inputURL(for record: UpscaleRecord) -> URL {
        root.appending(path: "\(record.id.uuidString)-input.\(record.inputExtension)")
    }

    func thumbnailURL(for record: UpscaleRecord) -> URL {
        root.appending(path: "\(record.id.uuidString)-thumb.jpg")
    }

    @discardableResult
    func save(result: UpscaleResult,
              sourceURL: URL,
              originalFilename: String,
              inputWidth: Int,
              inputHeight: Int,
              thumbnail: Data,
              context: ModelContext) throws -> UpscaleRecord {
        let inputBytes = byteCount(of: sourceURL)
        let outputBytes = byteCount(of: result.outputURL)

        let record = UpscaleRecord(
            originalFilename: originalFilename,
            appliedScale: result.appliedScale,
            requestedScale: result.requestedScale,
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            outputWidth: result.outputWidth,
            outputHeight: result.outputHeight,
            inputBytes: inputBytes,
            outputBytes: outputBytes,
            duration: result.duration,
            inputExtension: sourceURL.pathExtension.isEmpty ? "img" : sourceURL.pathExtension,
            outputExtension: result.outputURL.pathExtension
        )

        var destination = outputURL(for: record)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: result.outputURL, to: destination)
        try excludeFromBackup(&destination)

        // Copy, not move: the caller may still need the source, and on the
        // save-failed path the user retries against it.
        var inputCopy = inputURL(for: record)
        try? FileManager.default.removeItem(at: inputCopy)
        try FileManager.default.copyItem(at: sourceURL, to: inputCopy)
        try excludeFromBackup(&inputCopy)

        try thumbnail.write(to: thumbnailURL(for: record))

        context.insert(record)
        try context.save()
        return record
    }

    func delete(_ record: UpscaleRecord, context: ModelContext) throws {
        try? FileManager.default.removeItem(at: outputURL(for: record))
        try? FileManager.default.removeItem(at: inputURL(for: record))
        try? FileManager.default.removeItem(at: thumbnailURL(for: record))
        context.delete(record)
        try context.save()
    }

    func delete(_ records: [UpscaleRecord], context: ModelContext) throws {
        for record in records {
            try? FileManager.default.removeItem(at: outputURL(for: record))
            try? FileManager.default.removeItem(at: inputURL(for: record))
            try? FileManager.default.removeItem(at: thumbnailURL(for: record))
            context.delete(record)
        }
        try context.save()
    }

    func deleteAll(context: ModelContext) throws {
        try delete(try context.fetch(FetchDescriptor<UpscaleRecord>()), context: context)
    }

    /// Bytes actually on disk, which is what the Settings screen reports.
    func totalBytes() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func byteCount(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
