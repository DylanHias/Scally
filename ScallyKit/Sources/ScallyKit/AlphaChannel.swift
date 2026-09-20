import Foundation
import Accelerate

/// Carries transparency around the model, which only handles RGB.
///
/// The network has three input channels and no concept of transparency, so a
/// screenshot with rounded corners or a PNG logo would come back with its
/// transparency filled in as black if alpha were simply dropped. Alpha travels
/// separately: extracted before inference, scaled with Lanczos, reapplied after.
enum AlphaChannel {
    static func extract(from pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [UInt8] {
        var alpha = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                alpha[y * width + x] = pixels[rowStart + x * 4 + 3]
            }
        }
        return alpha
    }

    /// Lanczos resampling of the single-channel alpha plane.
    static func scaled(_ alpha: [UInt8],
                              from source: (width: Int, height: Int),
                              to destination: (width: Int, height: Int)) -> [UInt8] {
        var input = alpha
        var output = [UInt8](repeating: 0, count: destination.width * destination.height)

        input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                var sourceBuffer = vImage_Buffer(
                    data: inputBuffer.baseAddress,
                    height: vImagePixelCount(source.height),
                    width: vImagePixelCount(source.width),
                    rowBytes: source.width
                )
                var destinationBuffer = vImage_Buffer(
                    data: outputBuffer.baseAddress,
                    height: vImagePixelCount(destination.height),
                    width: vImagePixelCount(destination.width),
                    rowBytes: destination.width
                )
                vImageScale_Planar8(&sourceBuffer, &destinationBuffer, nil,
                                    vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return output
    }

    static func apply(_ alpha: [UInt8], to pixels: inout [UInt8],
                             width: Int, height: Int, bytesPerRow: Int) {
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                pixels[rowStart + x * 4 + 3] = alpha[y * width + x]
            }
        }
    }
}
