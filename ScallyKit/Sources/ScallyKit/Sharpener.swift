import Foundation
import CoreImage
import CoreGraphics

/// Unsharp masking applied after upscaling.
///
/// Every commercial upscaler does this and we did not. It cannot invent
/// detail - it raises acutance, the local contrast at edges, which is what
/// actually reads as "sharp" to a viewer. Overdone it produces halos, so the
/// default is deliberately modest.
public struct Sharpener: Sendable {
    /// 0 disables it entirely.
    public let intensity: Double
    /// Edge radius in output pixels. Small radius sharpens fine texture;
    /// large radius produces the halo look.
    public let radius: Double

    public static let none = Sharpener(intensity: 0, radius: 0)
    public static let standard = Sharpener(intensity: 0.45, radius: 1.6)

    /// Radius scaled for an upscale factor. Enlarging by 4x widens every edge
    /// by 4x, so a radius fixed in output pixels lands inside the edge and
    /// does almost nothing.
    public static func forUpscale(intensity: Double, scale: Int) -> Sharpener {
        Sharpener(intensity: intensity, radius: 0.9 * Double(scale))
    }

    public init(intensity: Double, radius: Double) {
        self.intensity = intensity
        self.radius = radius
    }

    public var isEnabled: Bool { intensity > 0.001 }

    /// How much of the sharpening survives inside a detected face. 0 would
    /// leave faces completely unsharpened, which reads as soft against a crisp
    /// background; a quarter keeps them coherent with the rest of the frame
    /// while removing the halo along the jaw and the plastic look on skin.
    public static let faceRetention = 0.25

    /// Returns a sharpened copy, or the original image when disabled.
    public func apply(to image: CGImage) -> CGImage {
        sharpenOnly(image)
    }

    /// Sharpens, but goes easy inside detected faces.
    ///
    /// Unsharp masking is exactly what makes an upscaled face look wrong: skin
    /// is low-contrast by nature, so raising acutance there manufactures pores
    /// and blotches that were not in the photograph, and the jawline picks up
    /// the classic halo. Damping it is the honest version of the promise the
    /// Configure screen makes - the face is left closer to what the camera
    /// recorded, rather than restored into someone slightly different.
    public func apply(to image: CGImage, softening faces: FaceRegions) -> CGImage {
        guard isEnabled else { return image }
        guard !faces.isEmpty else { return sharpenOnly(image) }

        let sharpened = sharpenOnly(image)
        guard let mask = Self.mask(for: faces, width: image.width, height: image.height),
              let blend = CIFilter(name: "CIBlendWithMask") else { return sharpened }

        // White in the mask takes the sharpened image, black takes the
        // original. The face ellipses are drawn at `faceRetention` grey, so
        // some sharpening still lands there.
        blend.setValue(CIImage(cgImage: sharpened), forKey: kCIInputImageKey)
        blend.setValue(CIImage(cgImage: image), forKey: kCIInputBackgroundImageKey)
        blend.setValue(CIImage(cgImage: mask), forKey: kCIInputMaskImageKey)
        guard let output = blend.outputImage else { return sharpened }

        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        return context.createCGImage(output, from: CIImage(cgImage: image).extent) ?? sharpened
    }

    /// White everywhere, with a soft grey ellipse over each face.
    ///
    /// The ellipse is blurred rather than hard-edged: a step change in
    /// sharpening along a face's bounding box is far more visible than the
    /// halo it was meant to remove.
    private static func mask(for faces: FaceRegions, width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: faceRetention, alpha: 1)

        var longestSide: CGFloat = 0
        for rectangle in faces.rectangles {
            // Vision's box is tight around the features; widen it so the
            // damping covers the whole face rather than stopping at the brow.
            // FaceRegions is top-left origin; a CGContext is bottom-left, so
            // the y has to be flipped back on the way in. Without this the
            // damping lands in the mirror image of the face - which a centred
            // test rectangle cannot detect, because it is its own reflection.
            let pixels = CGRect(x: rectangle.minX * CGFloat(width),
                                y: (1 - rectangle.maxY) * CGFloat(height),
                                width: rectangle.width * CGFloat(width),
                                height: rectangle.height * CGFloat(height))
                .insetBy(dx: -rectangle.width * CGFloat(width) * 0.12,
                         dy: -rectangle.height * CGFloat(height) * 0.12)
            context.fillEllipse(in: pixels)
            longestSide = max(longestSide, max(pixels.width, pixels.height))
        }

        guard let hard = context.makeImage() else { return nil }
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return hard }
        blur.setValue(CIImage(cgImage: hard), forKey: kCIInputImageKey)
        // Feather proportional to face size, so it scales with the image.
        blur.setValue(max(2, longestSide * 0.08), forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return hard }

        let ciContext = CIContext(options: [.workingColorSpace: space])
        return ciContext.createCGImage(blurred, from: CIImage(cgImage: hard).extent) ?? hard
    }

    private func sharpenOnly(_ image: CGImage) -> CGImage {
        guard isEnabled else { return image }
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        guard let output = filter.outputImage else { return image }

        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        // Crop back to the original extent: CIUnsharpMask expands it slightly.
        return context.createCGImage(output, from: input.extent) ?? image
    }
}
