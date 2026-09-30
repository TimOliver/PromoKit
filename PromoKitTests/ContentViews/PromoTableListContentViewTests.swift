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

    func testTableListContentViewLayoutsAfterPromoViewIsReleased() {
        var contentView: PromoTableListContentView!
        weak var releasedPromoView: PromoView?

        do {
            let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
            releasedPromoView = promoView
            contentView = PromoTableListContentView(promoView: promoView)
        }

        XCTAssertNil(releasedPromoView)
        XCTAssertNil(contentView.promoView)

        let image = makePromoTestImage(size: CGSize(width: 40, height: 40), color: .orange)
        contentView.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        contentView.configure(title: "Detached", detailText: "Still lays out", image: image)
        contentView.layoutIfNeeded()

        XCTAssertGreaterThan(contentView.imageView.frame.width, 0)
        XCTAssertGreaterThan(contentView.label.frame.width, 0)
    }

    func testLandscapeThumbnailPreservesAspectRatioAndLeavesRoomForText() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        let contentView = PromoTableListContentView(promoView: promoView)
        promoView.contentView = contentView
        let image = makePromoTestImage(size: CGSize(width: 800, height: 100), color: .blue)
        contentView.configure(title: "Important notice", detailText: "Read this announcement", image: image)

        for padding in [UIEdgeInsets.zero, UIEdgeInsets(top: 10, left: 16, bottom: 12, right: 20)] {
            for width in [320.0, 180.0, 400.0] {
                promoView.frame.size.width = width
                contentView.frame = promoView.bounds.inset(by: padding)
                contentView.setNeedsLayout()
                contentView.layoutIfNeeded()

                let imageFrame = contentView.imageView.frame
                let labelFrame = contentView.label.frame
                XCTAssertGreaterThan(imageFrame.width, 0)
                XCTAssertGreaterThan(labelFrame.width, 0,
                                     "A landscape thumbnail must leave a visible text column")
                XCTAssertGreaterThanOrEqual(labelFrame.width, imageFrame.width)
                XCTAssertEqual(imageFrame.width / imageFrame.height, 8, accuracy: 0.001)
                XCTAssertEqual(imageFrame.midY, contentView.bounds.midY, accuracy: 0.001)
                XCTAssertEqual(labelFrame.minX - imageFrame.maxX, padding.left, accuracy: 0.001)
                XCTAssertLessThanOrEqual(imageFrame.maxX, contentView.bounds.maxX)
                XCTAssertLessThanOrEqual(imageFrame.maxY, contentView.bounds.maxY)
                XCTAssertLessThanOrEqual(labelFrame.maxX, contentView.bounds.maxX)
            }
        }
    }

    func testPortraitThumbnailPreservesAspectRatioAndClearsItsFrameWhenRemoved() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let contentView = PromoTableListContentView(promoView: promoView)
        contentView.frame = promoView.bounds
        contentView.configure(title: "Notice", image: makePromoTestImage(size: CGSize(width: 40, height: 80), color: .red))
        contentView.layoutIfNeeded()

        XCTAssertEqual(contentView.imageView.frame.width / contentView.imageView.frame.height, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(contentView.label.frame.width, 0)

        contentView.configure(title: "Notice without an image")
        contentView.layoutIfNeeded()
        XCTAssertTrue(contentView.imageView.isHidden)
        XCTAssertEqual(contentView.imageView.frame, .zero)
        XCTAssertEqual(contentView.label.frame.width, contentView.bounds.width)
    }
}
