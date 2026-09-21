import Foundation
import Observation
import ScallyKit

@Observable
@MainActor
final class ProcessingModel {
    enum State: Equatable {
        case idle, running, finished(UpscaleResult), failed(String), cancelled
    }

    private(set) var progress: Double = 0
    private(set) var state: State = .idle
    private var elapsedAtLastSample: TimeInterval = 0
    private var task: Task<Void, Never>?

    var elapsed: TimeInterval { elapsedAtLastSample }

    /// Linear extrapolation from observed throughput. Tiles are uniform work,
    /// so this is honest rather than decorative.
    var estimatedRemaining: TimeInterval? {
        guard progress > 0.01, elapsedAtLastSample > 0 else { return nil }
        return max(0, elapsedAtLastSample / progress - elapsedAtLastSample)
    }

    func recordProgress(_ value: Double, elapsed: TimeInterval) {
        progress = value
        elapsedAtLastSample = elapsed
    }

    func start(source: URL, scale: Int, sharpen: Double = 0.45) {
        guard case .idle = state else { return }
        state = .running
        let started = Date()

        // `self` is captured strongly and deliberately: the type is @MainActor
        // and therefore Sendable, whereas a weak capture inside the @Sendable
        // progress closure is not expressible. The cycle is broken by clearing
        // `task` when the run ends.
        task = Task { [self] in
            do {
                let pipeline = UpscalePipeline(
                    upscaler: try CoreMLUpscaler(modelName: "NomosWebPhoto"),
                    faceRestorer: NoopFaceRestorer(),
                    faceDetector: VisionFaceDetector(),
                    sharpener: .forUpscale(intensity: sharpen, scale: scale),
                    scratchDirectory: FileManager.default.urls(for: .cachesDirectory,
                                                               in: .userDomainMask)[0]
                )
                let result = try await pipeline.run(source: source, requestedScale: scale) { value in
                    Task { @MainActor in
                        self.recordProgress(value, elapsed: Date().timeIntervalSince(started))
                    }
                }
                state = .finished(result)
            } catch is CancellationError {
                state = .cancelled
            } catch {
                state = .failed(error.localizedDescription)
            }
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        state = .cancelled
    }
}
