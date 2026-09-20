import Foundation
import ScallyKit

/// Which model does the upscaling.
///
/// Diffusion is non-commercially licensed (ResShift S-Lab 1.0, RSD
/// CC BY-NC-SA 4.0), which is only acceptable because Scally is free.
enum UpscaleEngine: String, CaseIterable, Identifiable {
    case fast
    case best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .best: "Best"
        }
    }

    var detail: String {
        switch self {
        case .fast: "Real-ESRGAN, 17M parameters. A few seconds."
        case .best: "One-step diffusion, 119M parameters. Invents detail. Slower."
        }
    }

    func makeUpscaler() throws -> any Upscaler {
        switch self {
        case .fast: try CoreMLUpscaler()
        case .best: try ResShiftUpscaler()
        }
    }
}
