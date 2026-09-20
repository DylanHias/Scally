import Foundation
import CoreGraphics

/// An RGBA8 image buffer backed by a memory-mapped scratch file.
///
/// A 4x upscale of a 12MP photo is ~770MB of pixels. Holding that in the heap
/// gets the process killed, so it lives in a file the kernel pages in and out
/// on demand, keeping resident memory flat regardless of output size.
///
/// The backing file is scratch storage and is deleted when this object
/// deinitialises. It is not the final output, which `OutputWriter` encodes
/// separately.
final class MappedPixelBuffer {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let fileURL: URL
    let baseAddress: UnsafeMutableRawPointer

    private let descriptor: Int32
    private let byteCount: Int

    init(width: Int, height: Int, directory: URL) throws {
        precondition(width > 0 && height > 0, "buffer must have area")
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.byteCount = bytesPerRow * height
        self.fileURL = directory.appendingPathComponent("scally-\(UUID().uuidString).raw")

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        descriptor = open(fileURL.path, O_RDWR)
        guard descriptor >= 0 else {
            throw UpscaleError.scratchAllocationFailed(underlying: errno)
        }

        guard ftruncate(descriptor, off_t(byteCount)) == 0 else {
            let code = errno
            close(descriptor)
            try? FileManager.default.removeItem(at: fileURL)
            throw UpscaleError.scratchAllocationFailed(underlying: code)
        }

        let mapped = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0)
        guard let mapped, mapped != MAP_FAILED else {
            let code = errno
            close(descriptor)
            try? FileManager.default.removeItem(at: fileURL)
            throw UpscaleError.scratchAllocationFailed(underlying: code)
        }
        self.baseAddress = mapped
    }

    deinit {
        munmap(baseAddress, byteCount)
        close(descriptor)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Wraps the mapping in a CGImage without copying it.
    ///
    /// The provider's release callback is intentionally empty: the mapping
    /// outlives the CGImage and is torn down in `deinit`.
    func makeCGImage() throws -> CGImage {
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: baseAddress,
            size: byteCount,
            releaseData: { _, _, _ in }
        ) else { throw UpscaleError.encodingFailed }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw UpscaleError.encodingFailed }

        return image
    }
}
