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

    func testImageProcessingBlurredImageWithoutFittingSizeReturnsImage() {
        // Exercises the branch in blurredImage that skips the scale-down transform when no
        // fittingSize is provided.
        let source = makePromoTestImage(size: CGSize(width: 40, height: 40), color: .systemTeal)
        let blurred = PromoImageProcessing.blurredImage(source, radius: 5)
        XCTAssertNotNil(blurred)
    }

    func testImageProcessingBlurredImageReturnsNilForEmptyImage() {
        XCTAssertNil(PromoImageProcessing.blurredImage(UIImage(), radius: 5))
    }

    func testImageProcessingDecodedImageWithoutFittingSizeProducesACGImage() {
        // Exercises the default-fittingSize branch of decodedImage where the helper falls
        // back to the source image's intrinsic size.
        let source = makePromoTestImage(size: CGSize(width: 64, height: 32), color: .magenta)
        let decoded = PromoImageProcessing.decodedImage(source, scale: 1.0)
        XCTAssertNotNil(decoded)
        XCTAssertNotNil(decoded?.cgImage)
    }

    func testImageProcessingDecodedImageReturnsNilForCGImagelessInput() {
        // CIImage-only UIImages have no backing cgImage — decodedImage should bail early
        // via its guard rather than try to feed the image through the thumbnail/CGContext path.
        let ciOnlyImage = UIImage(ciImage: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0,
                                                                                    width: 4,
                                                                                    height: 4)))
        XCTAssertNil(PromoImageProcessing.decodedImage(ciOnlyImage))
    }

    func testImageProcessingLegacyDecodedImageDownscalesAndPreservesScale() throws {
        let source = makePromoTestImage(size: CGSize(width: 120, height: 60), color: .orange)
        let cgImage = try XCTUnwrap(source.cgImage)
        let fittingSize = CGSize(width: 30, height: 100)
        let outputScale: CGFloat = 2.0

        let decoded = try XCTUnwrap(PromoImageProcessing.decodedImage(source,
                                                                      fittingSize: fittingSize,
                                                                      scale: outputScale,
                                                                      useSystemThumbnailPreparation: false))
        let expectedSize = PromoImageProcessing.size(CGSize(width: cgImage.width, height: cgImage.height),
                                                     fitting: fittingSize)

        XCTAssertEqual(decoded.scale, outputScale)
        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertEqual(decoded.cgImage?.width, Int(expectedSize.width * outputScale))
        XCTAssertEqual(decoded.cgImage?.height, Int(expectedSize.height * outputScale))
    }

    func testImageProcessingLegacyDecodedImageReturnsNilForInvalidFittingSize() throws {
        let source = makePromoTestImage(size: CGSize(width: 20, height: 20), color: .purple)

        XCTAssertNil(PromoImageProcessing.decodedImage(source,
                                                       fittingSize: .zero,
                                                       scale: 1.0,
                                                       useSystemThumbnailPreparation: false))
    }

    func testImageProcessingFittingSizePreservesAspectRatio() {
        XCTAssertEqual(PromoImageProcessing.size(CGSize(width: 120, height: 60), fitting: nil),
                       CGSize(width: 120, height: 60))
        XCTAssertEqual(PromoImageProcessing.size(CGSize(width: 120, height: 60),
                                                 fitting: CGSize(width: 30, height: 100)),
                       CGSize(width: 30, height: 15))
        XCTAssertEqual(PromoImageProcessing.size(CGSize(width: 60, height: 120),
                                                 fitting: CGSize(width: 100, height: 30)),
                       CGSize(width: 15, height: 30))
        XCTAssertEqual(PromoImageProcessing.size(CGSize(width: 20, height: 10),
                                                 fitting: CGSize(width: 100, height: 100)),
                       CGSize(width: 100, height: 50))
    }
}
