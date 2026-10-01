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

    func testLongFootnoteStaysInsideTextColumnWithAndWithoutAnImage() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let contentView = PromoTableListContentView(promoView: promoView)
        promoView.contentView = contentView
        let image = makePromoTestImage(size: CGSize(width: 40, height: 40), color: .blue)

        for padding in [UIEdgeInsets.zero, UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 12)] {
            for thumbnail in [nil, image] {
                contentView.frame = promoView.bounds.inset(by: padding)
                contentView.configure(title: "Notice", footnote: "announcements.very-long-application-name.example.com", image: thumbnail)
                contentView.layoutIfNeeded()

                XCTAssertFalse(contentView.footnoteLabel.isHidden)
                XCTAssertGreaterThan(contentView.footnoteLabel.frame.height, 0)
                XCTAssertEqual(contentView.footnoteLabel.frame.minX, contentView.label.frame.minX)
                XCTAssertLessThanOrEqual(contentView.footnoteLabel.frame.maxX, contentView.bounds.maxX)
                XCTAssertLessThanOrEqual(contentView.footnoteLabel.frame.maxY, contentView.bounds.maxY)
                XCTAssertGreaterThan(contentView.footnoteLabel.frame.minY, contentView.label.frame.maxY)
            }
        }
    }

    func testFootnoteAndTitleRemainInsideShortBoundsAfterResizing() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let contentView = PromoTableListContentView(promoView: promoView)
        contentView.frame = promoView.bounds
        contentView.configure(title: "A notice with a long title", detailText: "More information", footnote: "example.com")
        contentView.layoutIfNeeded()

        for height in [24.0, 10.0, 80.0] {
            contentView.frame.size = CGSize(width: 120, height: height)
            contentView.setNeedsLayout()
            contentView.layoutIfNeeded()

            XCTAssertGreaterThanOrEqual(contentView.label.frame.minY, 0)
            XCTAssertLessThanOrEqual(contentView.label.frame.maxY, contentView.footnoteLabel.frame.minY)
            XCTAssertLessThanOrEqual(contentView.footnoteLabel.frame.maxX, contentView.bounds.maxX)
            XCTAssertLessThanOrEqual(contentView.footnoteLabel.frame.maxY, contentView.bounds.maxY)
        }
    }

    func testRemovingFootnoteClearsItsFrameAndReturnsSpaceToTheTitle() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let contentView = PromoTableListContentView(promoView: promoView)
        contentView.frame = promoView.bounds

        for footnote in [nil, ""] {
            contentView.configure(title: "Notice", footnote: "example.com")
            contentView.layoutIfNeeded()
            XCTAssertGreaterThan(contentView.footnoteLabel.frame.height, 0)

            contentView.configure(title: "Notice", footnote: footnote)
            contentView.layoutIfNeeded()
            XCTAssertTrue(contentView.footnoteLabel.isHidden)
            XCTAssertEqual(contentView.footnoteLabel.frame, .zero)
            XCTAssertEqual(contentView.label.frame.midY, contentView.bounds.midY, accuracy: 0.001)
        }

        contentView.configure(title: "Notice", footnote: "example.com")
        contentView.layoutIfNeeded()
        contentView.prepareForReuse()
        XCTAssertNil(contentView.footnoteLabel.text)
        XCTAssertTrue(contentView.footnoteLabel.isHidden)
        XCTAssertEqual(contentView.footnoteLabel.frame, .zero)

        contentView.configure(title: "Reused notice", footnote: "example.com")
        contentView.layoutIfNeeded()
        XCTAssertFalse(contentView.footnoteLabel.isHidden)
        XCTAssertGreaterThan(contentView.footnoteLabel.frame.height, 0)
    }
}

extension PromoTableListContentViewTests {
    func testTableFontsAndPreferredHeightRespondToContentSizeChanges() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.traitOverrides.preferredContentSizeCategory = .large
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        controller.view.addSubview(promo)
        let provider = PromoAppRaterProvider()
        let content = try XCTUnwrap(provider.contentView(for: promo) as? PromoTableListContentView)
        promo.addSubview(content)
        content.configure(title: "Title", detailText: "Detail", footnote: "Footnote",
                          image: makePromoTestImage(size: CGSize(width: 60, height: 60), color: .blue))
        window.layoutIfNeeded()

        func fontSizes() throws -> [CGFloat] {
            let text = try XCTUnwrap(content.label.attributedText)
            return [try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont).pointSize,
                    try XCTUnwrap(text.attribute(.font, at: 6, effectiveRange: nil) as? UIFont).pointSize,
                    content.footnoteLabel.font.pointSize]
        }
        let fittingSize = CGSize(width: 320, height: 900)
        let normalFonts = try fontSizes()
        let normalSize = content.sizeThatFits(fittingSize)
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.layoutIfNeeded()
        XCTAssertEqual(content.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        for (normal, accessible) in zip(normalFonts, try fontSizes()) {
            XCTAssertGreaterThan(accessible, normal)
        }
        let accessibleSize = content.sizeThatFits(fittingSize)
        XCTAssertGreaterThan(accessibleSize.height, normalSize.height)
        XCTAssertEqual(accessibleSize.width, normalSize.width)
        XCTAssertFalse(content.label.adjustsFontSizeToFitWidth)
        content.frame = CGRect(origin: .zero, size: accessibleSize)
        content.layoutIfNeeded()
        XCTAssertLessThanOrEqual(content.imageView.frame.height, 75)
        XCTAssertGreaterThanOrEqual(content.label.frame.height,
                                    content.label.sizeThatFits(CGSize(width: content.label.frame.width,
                                                                     height: .greatestFiniteMagnitude)).height)
        XCTAssertLessThanOrEqual(content.footnoteLabel.frame.maxY, content.bounds.maxY)
        let capped = content.sizeThatFits(CGSize(width: 100, height: 40))
        XCTAssertEqual(capped.width, 100)
        XCTAssertLessThanOrEqual(capped.height, 40)

        controller.traitOverrides.preferredContentSizeCategory = .large
        window.layoutIfNeeded()
        XCTAssertEqual(try fontSizes(), normalFonts)
        XCTAssertEqual(content.sizeThatFits(fittingSize), normalSize)
        content.prepareForReuse()
        XCTAssertFalse(content.wantsSizingControl)
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.layoutIfNeeded()
        XCTAssertNil(content.label.attributedText)
    }

    func testContentSizeChangeNotifiesTheActiveHostWithoutRefetching() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.traitOverrides.preferredContentSizeCategory = .large
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        controller.view.addSubview(promo)
        let content = PromoTableListContentView(promoView: promo)
        content.preferredSize = CGSize(width: 450, height: 75)
        promo.addSubview(content)
        content.configure(title: "Announcement", detailText: "Please read these details")
        window.layoutIfNeeded()
        let provider = TestPromoProvider(result: .contentAvailable)
        let delegate = PromoViewDelegateSpy()
        promo.currentProvider = provider
        promo.contentView = content
        promo.delegate = delegate

        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.layoutIfNeeded()
        wait(for: [delegate.updateExpectation], timeout: 1)
        XCTAssertEqual(delegate.updateCount, 1)
        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertTrue(promo.contentView === content)
        XCTAssertGreaterThan(promo.sizeThatFits(CGSize(width: 320, height: 900)).height, 100)
    }

    func testReusingATableCancelsItsPendingSizingNotification() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.traitOverrides.preferredContentSizeCategory = .large
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        controller.view.addSubview(promo)
        let content = PromoTableListContentView(promoView: promo)
        promo.addSubview(content)
        content.configure(title: "Old announcement")
        window.layoutIfNeeded()
        let delegate = PromoViewDelegateSpy()
        promo.delegate = delegate
        promo.currentProvider = TestPromoProvider(result: .contentAvailable)
        promo.contentView = content
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.layoutIfNeeded()
        content.prepareForReuse()
        content.configure(title: "Replacement")
        let drained = expectation(description: "Pending sizing notification drains")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(delegate.updateCount, 0)
        XCTAssertEqual(content.label.text, "Replacement")
    }
}
