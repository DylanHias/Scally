import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OutputWriter {
    enum Format: Sendable {
        case png
        case heic(quality: Double)

        /// HEIC's alpha handling is inconsistent and lossy edges on
        /// transparency look bad, so anything with alpha goes to PNG.
        static func preferred(hasAlpha: Bool) -> Format {
            hasAlpha ? .png : .heic(quality: 0.92)
        }

        var isPNG: Bool { if case .png = self { return true } else { return false } }

        var contentType: UTType {
            switch self {
            case .png: .png
            case .heic: .heic
            }
        }

        var fileExtension: String { isPNG ? "png" : "heic" }
    }

    /// Encodes the scratch buffer to a real image file.
    ///
    /// Reading back through the mapping is sequential, which is the access
    /// pattern the pager handles best - memory stays flat even for very large
    /// outputs.
    static func write(buffer: MappedPixelBuffer, to url: URL, format: Format,
                      sharpener: Sharpener = .none,
                      faces: FaceRegions = .none) throws {
        let image = sharpener.apply(to: try buffer.makeCGImage(), softening: faces)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil
        ) else { throw UpscaleError.encodingFailed }

        var options: [CFString: Any] = [:]
        if case .heic(let quality) = format {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw UpscaleError.encodingFailed }
    }
}
