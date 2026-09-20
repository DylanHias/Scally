import Testing
@testable import ScallyKit

@Test func generousBudgetGrantsTheRequestedScale() {
    let budget = MemoryBudget(availableBytes: 4_000_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 4032, inputHeight: 3024)
    #expect(decision == .granted(scale: 4))
}

@Test func tightBudgetClampsFourToTwo() {
    // 4032x3024 at 4x is ~780MB; at 2x it is ~195MB.
    let budget = MemoryBudget(availableBytes: 400_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 4032, inputHeight: 3024)
    #expect(decision == .clamped(scale: 2, requested: 4))
}

@Test func budgetTooSmallForEvenTwoIsRefused() {
    let budget = MemoryBudget(availableBytes: 10_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 4032, inputHeight: 3024)
    if case .refused = decision {} else {
        Issue.record("expected refusal, got \(decision)")
    }
}

@Test func smallImagesAreAlwaysGranted() {
    let budget = MemoryBudget(availableBytes: 200_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 800, inputHeight: 600)
    #expect(decision == .granted(scale: 4))
}

@Test func outputByteCountIsWidthTimesHeightTimesFour() {
    #expect(MemoryBudget.outputBytes(width: 100, height: 50, scale: 2) == 100 * 2 * 50 * 2 * 4)
}

@Test func requestingTwoOnATightBudgetIsRefusedNotClampedUpward() {
    // There is nothing below 2x, so a 2x request that does not fit is refused.
    let budget = MemoryBudget(availableBytes: 1_000_000)
    let decision = budget.resolveScale(requested: 2, inputWidth: 4032, inputHeight: 3024)
    if case .refused = decision {} else {
        Issue.record("expected refusal, got \(decision)")
    }
}

@Test func decisionExposesTheScaleItResolvedTo() {
    #expect(ScaleDecision.granted(scale: 4).scale == 4)
    #expect(ScaleDecision.clamped(scale: 2, requested: 4).scale == 2)
    #expect(ScaleDecision.refused(requiredBytes: 1, availableBytes: 0).scale == nil)
}

@Test func theRealBudgetIsPositive() {
    // Guards the platform shim: a zero budget would refuse every upscale.
    #expect(MemoryBudget.current().availableBytes > 0)
}

@Test func theRealBudgetAlwaysGrantsASmallUpscale() {
    // The bug this covers: os_proc_available_memory() reports 0 on the
    // simulator, so the real budget refused a 120x120 image outright. Whatever
    // the platform reports, a thumbnail-sized upscale must always be possible.
    let decision = MemoryBudget.current().resolveScale(requested: 4, inputWidth: 120, inputHeight: 120)
    #expect(decision == .granted(scale: 4), "a 120x120 image was not granted: \(decision)")
}

@Test func animplausiblyLowReadingStillGrantsModestWork() {
    // A genuinely tiny injected budget is still honoured - the floor applies to
    // the platform reading, not to explicitly supplied budgets.
    let injected = MemoryBudget(availableBytes: 1000)
    if case .refused = injected.resolveScale(requested: 4, inputWidth: 4032, inputHeight: 3024) {} else {
        Issue.record("an explicit tiny budget must still refuse large work")
    }
}
