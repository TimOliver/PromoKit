import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoTableListContentViewTests: XCTestCase {

    func testTableListContentViewConfigurationAndReuseLifecycle() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let contentView = PromoTableListContentView(promoView: promoView)
        let testImage = makePromoTestImage(size: CGSize(width: 30, height: 30), color: .red)

        contentView.configure(title: "Hello", detailText: "World", footnote: "subtitle", image: testImage)
        XCTAssertEqual(contentView.label.attributedText?.string, "Hello\nWorld")
        XCTAssertEqual(contentView.footnoteLabel.text, "subtitle")
        XCTAssertNotNil(contentView.imageView.image)
        XCTAssertFalse(contentView.imageView.isHidden)

        contentView.configure(title: "Title-only")
        XCTAssertNil(contentView.imageView.image)
        XCTAssertTrue(contentView.imageView.isHidden,
                      "Reconfiguring without an image should hide the image view")

        contentView.prepareForReuse()
        XCTAssertNil(contentView.label.text)
        XCTAssertNil(contentView.footnoteLabel.text)
        XCTAssertNil(contentView.imageView.image)
    }

    func testTableListContentViewLayoutPositionsImageAndLabels() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        let contentView = PromoTableListContentView(promoView: promoView)
        contentView.frame = CGRect(x: 0, y: 0, width: 320, height: 80)

        let image = makePromoTestImage(size: CGSize(width: 60, height: 60), color: .blue)
        contentView.configure(title: "Title", detailText: "Detail line", footnote: "footnote", image: image)
        contentView.layoutIfNeeded()

        XCTAssertGreaterThan(contentView.imageView.frame.width, 0,
                             "Image view should be sized after layout when an image is present")
        XCTAssertGreaterThanOrEqual(contentView.label.frame.minX, contentView.imageView.frame.maxX,
                                    "Label should start at or after the image's trailing edge")
        XCTAssertGreaterThan(contentView.footnoteLabel.frame.height, 0,
                             "Footnote should be measured when text is present")
    }
}
