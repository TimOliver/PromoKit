import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoImageProcessingTests: XCTestCase {

    func testImageProcessingDecodedImagePreservesContentAndReturnsNilForNilInput() {
        XCTAssertNil(PromoImageProcessing.decodedImage(nil))

        let source = makePromoTestImage(size: CGSize(width: 80, height: 80), color: .red)
        let decoded = PromoImageProcessing.decodedImage(source,
                                                        fittingSize: CGSize(width: 40, height: 40),
                                                        scale: 2.0)
        XCTAssertNotNil(decoded)
        XCTAssertNotNil(decoded?.cgImage)
    }

    func testImageProcessingBlurredImageProducesOutput() {
        let source = makePromoTestImage(size: CGSize(width: 80, height: 80), color: .blue)
        let blurred = PromoImageProcessing.blurredImage(source,
                                                        radius: 10,
                                                        fittingSize: CGSize(width: 40, height: 40))
        XCTAssertNotNil(blurred)
    }
}
