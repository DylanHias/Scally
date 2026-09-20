import Foundation
#if canImport(os)
import os
#endif

public enum ScaleDecision: Sendable, Equatable {
    case granted(scale: Int)
    case clamped(scale: Int, requested: Int)
    case refused(requiredBytes: Int, availableBytes: Int)

    public var scale: Int? {
        switch self {
        case .granted(let scale): scale
        case .clamped(let scale, _): scale
        case .refused: nil
        }
    }
}

/// Decides whether an upscale fits before it starts.
///
/// The scratch buffer is memory-mapped, so the kernel can page it out - but
/// dirty pages still count against the process while they are being written,
/// and an old iPhone on a 12MP photo is a case that genuinely happens. Better
/// to clamp and tell the user up front than to be killed mid-run.
public struct MemoryBudget: Sendable {
    /// Fraction of the remaining allowance we are willing to commit.
    private static let safetyFactor = 0.6

    /// Smallest scale the app offers. Nothing clamps below this.
    private static let minimumScale = 2

    public let availableBytes: Int

    public init(availableBytes: Int) {
        self.availableBytes = availableBytes
    }

    /// The real remaining allowance for this process.
    ///
    /// `os_proc_available_memory` is iOS-only. On macOS - where the package's
    /// tests run - there is no per-process jetsam limit to read, so a
    /// conservative fraction of physical memory stands in. The value only has
    /// to be sane there; the clamping logic itself is tested with an injected
    /// budget precisely so it never depends on this shim.
    public static func current() -> MemoryBudget {
        #if os(iOS)
        return MemoryBudget(availableBytes: Int(os_proc_available_memory()))
        #else
        let physical = ProcessInfo.processInfo.physicalMemory
        return MemoryBudget(availableBytes: Int(physical / 4))
        #endif
    }

    public static func outputBytes(width: Int, height: Int, scale: Int) -> Int {
        width * scale * height * scale * 4
    }

    public func resolveScale(requested: Int, inputWidth: Int, inputHeight: Int) -> ScaleDecision {
        let ceiling = Int(Double(availableBytes) * Self.safetyFactor)

        let requestedBytes = Self.outputBytes(width: inputWidth, height: inputHeight, scale: requested)
        if requestedBytes <= ceiling {
            return .granted(scale: requested)
        }

        if requested > Self.minimumScale {
            for fallback in stride(from: requested - 1, through: Self.minimumScale, by: -1) {
                let bytes = Self.outputBytes(width: inputWidth, height: inputHeight, scale: fallback)
                if bytes <= ceiling {
                    return .clamped(scale: fallback, requested: requested)
                }
            }
        }

        let minimumBytes = Self.outputBytes(width: inputWidth, height: inputHeight, scale: Self.minimumScale)
        return .refused(requiredBytes: minimumBytes, availableBytes: ceiling)
    }
}
