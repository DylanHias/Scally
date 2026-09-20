import Testing
@testable import ScallyKit

@Test func errorsCarryReadableDescriptions() {
    let error = UpscaleError.unsupportedImageFormat
    #expect(error.errorDescription?.isEmpty == false)
}

@Test func errorsWithPayloadsIncludeTheirValues() {
    #expect(UpscaleError.inferenceFailed(tileIndex: 7).errorDescription?.contains("7") == true)
    #expect(UpscaleError.imageTooLarge(pixels: 1234).errorDescription?.contains("1234") == true)
}
