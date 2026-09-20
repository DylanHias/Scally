import Testing
@testable import ScallyKit

/// Proves the app test target links ScallyKit. Replaced by real tests from Task 15 onward.
@Test func appTargetCanReachScallyKit() {
    #expect(UpscaleError.cancelled.errorDescription == "Cancelled.")
}
