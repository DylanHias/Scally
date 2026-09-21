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

    /// Returns a sharpened copy, or the original image when disabled.
    public func apply(to image: CGImage) -> CGImage {
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
