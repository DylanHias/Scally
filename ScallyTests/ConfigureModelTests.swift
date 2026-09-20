import Testing
import Foundation
@testable import Scally
@testable import ScallyKit

private let generous = MemoryBudget(availableBytes: 4_000_000_000)

@Test func generousBudgetOffersBothScales() {
    let model = ConfigureModel(inputWidth: 1000, inputHeight: 800, budget: generous)
    #expect(model.isAvailable(scale: 2))
    #expect(model.isAvailable(scale: 4))
    #expect(model.availableScales == [2, 4])
}

@Test func tightBudgetDisablesFourTimes() {
    let model = ConfigureModel(inputWidth: 3024, inputHeight: 4032,
                               budget: MemoryBudget(availableBytes: 400_000_000))
    #expect(model.isAvailable(scale: 2))
    #expect(model.isAvailable(scale: 4) == false)
    #expect(model.availableScales == [2])
}

@Test func outputDimensionsMultiplyBothAxes() {
    let model = ConfigureModel(inputWidth: 300, inputHeight: 200, budget: generous)
    let size = model.outputDimensions(scale: 4)
    #expect(size.width == 1200)
    #expect(size.height == 800)
}

@Test func defaultScaleIsTheLargestAvailable() {
    #expect(ConfigureModel(inputWidth: 500, inputHeight: 500, budget: generous).defaultScale == 4)
    #expect(ConfigureModel(inputWidth: 3024, inputHeight: 4032,
                           budget: MemoryBudget(availableBytes: 400_000_000)).defaultScale == 2)
}

@Test func unavailableReasonNamesTheRequirementAndTheAlternative() {
    let model = ConfigureModel(inputWidth: 3024, inputHeight: 4032,
                               budget: MemoryBudget(availableBytes: 400_000_000))
    let reason = try! #require(model.unavailableReason(scale: 4))
    #expect(reason.contains("4×"))
    #expect(reason.contains("GB") || reason.contains("MB"), "must state the real requirement: \(reason)")
    #expect(reason.contains("2× is available."))
}

@Test func availableScalesHaveNoReason() {
    let model = ConfigureModel(inputWidth: 500, inputHeight: 500, budget: generous)
    #expect(model.unavailableReason(scale: 4) == nil)
    #expect(model.unavailableReason(scale: 2) == nil)
}

@Test func tileCountMatchesTheGridThePipelineWillBuild() {
    // Must agree with ScallyKit's TileGrid or the estimate lies.
    for (w, h) in [(100, 80), (700, 500), (3024, 4032), (256, 256), (257, 257)] {
        let model = ConfigureModel(inputWidth: w, inputHeight: h, budget: generous)
        let grid = TileGrid(imageWidth: w, imageHeight: h, tileSize: 256, overlap: 16)
        #expect(model.tileCount == grid.tiles.count,
                "\(w)x\(h): model says \(model.tileCount), grid has \(grid.tiles.count)")
    }
}

@Test func estimateIsAtLeastOneSecond() {
    let model = ConfigureModel(inputWidth: 32, inputHeight: 32, budget: generous)
    #expect(model.estimatedSeconds(scale: 4) >= 1)
}

@Test func estimatedFileSizeGrowsWithScale() {
    let model = ConfigureModel(inputWidth: 500, inputHeight: 500, budget: generous)
    #expect(model.estimatedBytes(scale: 4) > model.estimatedBytes(scale: 2))
}
