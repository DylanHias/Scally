import Foundation
import CoreGraphics
import CoreImage
import ImageIO

/// An image in canonical form: RGBA8, sRGB, upright.
public struct LoadedImage: Sendable {
    public let pixels: [UInt8]
    public let width: Int
    public let height: Int
    public let hasAlpha: Bool

    public var bytesPerRow: Int { width * 4 }

    /// A CGImage over a copy of these pixels, for the frameworks that want one.
    public func makeCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: space,
                       bitmapInfo: CGBitmapInfo(
                           rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}

public enum ImageLoader {
    private static let workingColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func load(url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw UpscaleError.unsupportedImageFormat
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
        return try render(image, orientation: orientation)
    }

    /// Applies EXIF orientation and converts to sRGB RGBA8.
    ///
    /// `CIImage.oriented(_:)` handles all eight EXIF cases; hand-rolled affine
    /// transforms get the four mirrored ones subtly wrong.
    ///
    /// Display P3 and HDR inputs are flattened to sRGB here. That loses gamut
    /// on vivid photographs and is an accepted v1 tradeoff (spec section 6) -
    /// the model was trained on sRGB and feeding it P3 shifts colours far worse.
    public static func render(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> LoadedImage {
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let context = CIContext(options: [.workingColorSpace: workingColorSpace])

        guard let converted = context.createCGImage(
            oriented,
            from: oriented.extent,
            format: .RGBA8,
            colorSpace: workingColorSpace
        ) else { throw UpscaleError.unsupportedImageFormat }

        let width = converted.width
        let height = converted.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        try pixels.withUnsafeMutableBytes { raw in
            guard let bitmap = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: workingColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw UpscaleError.unsupportedImageFormat }
            bitmap.draw(converted, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return LoadedImage(pixels: pixels, width: width, height: height,
                           hasAlpha: transparencyIsUsed(in: pixels))
    }
}

private extension ImageLoader {
    /// Whether transparency is actually *used*, not merely declared.
    ///
    /// PNG screenshots almost always carry a fully opaque alpha channel. Taking
    /// the declared `alphaInfo` at face value would route every one of them to
    /// PNG output instead of HEIC - several times the file size for no benefit -
    /// and screenshots are the primary input this app exists for. So scan.
    static func transparencyIsUsed(in pixels: [UInt8]) -> Bool {
        var index = 3
        while index < pixels.count {
            if pixels[index] != 255 { return true }
            index += 4
        }
        return false
    }
}
