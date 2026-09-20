import Foundation

/// Restores faces in an already-upscaled image, in place.
///
/// This protocol exists in v1 with only a no-op implementation, deliberately.
/// Every strong open face-restoration model (CodeFormer, GFPGAN, and most
/// alternatives via FFHQ) carries non-commercial licensing, so keeping this
/// behind an interface is what makes the decision to add or abandon it a
/// one-type change rather than a rewrite. See spec section 2.
public protocol FaceRestorer: Sendable {
    /// Returns true if any pixels were modified.
    func restore(image: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> Bool
}

public struct NoopFaceRestorer: FaceRestorer {
    public init() {}

    public func restore(image: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> Bool {
        false
    }
}
