import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoViewDisplayTests: XCTestCase {

    func testCloseButtonTapFiresDelegateCallback() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate
        promoView.showCloseButton = true
        promoView.layoutIfNeeded()

        guard let closeButton = promoView.subviews.compactMap({ $0 as? UIButton }).first else {
            return XCTFail("Close button should be present after enabling showCloseButton")
        }

        closeButton.sendActions(for: .touchUpInside)

        XCTAssertEqual(delegate.closeTapCount, 1)
    }

    func testCloseButtonExpandsHitTestArea() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promoView.showCloseButton = true
        promoView.layoutIfNeeded()

        guard let closeButton = promoView.subviews.compactMap({ $0 as? UIButton }).first else {
            return XCTFail("Close button should be present after enabling showCloseButton")
        }

        // Hit-testing inside the visual frame returns the button itself…
        let visualCenter = CGPoint(x: closeButton.frame.midX, y: closeButton.frame.midY)
        XCTAssertTrue(promoView.hitTest(visualCenter, with: nil) === closeButton)

        // …and the expanded touch target (insetBy -10) still routes hits to the button.
        let nearMissPoint = CGPoint(x: closeButton.frame.minX - 6, y: closeButton.frame.minY - 6)
        XCTAssertTrue(promoView.point(inside: nearMissPoint, with: nil),
                      "Points just outside the button should still register as inside the promo view")
        XCTAssertTrue(promoView.hitTest(nearMissPoint, with: nil) === closeButton)
    }

    func testTotalBoundsSizeIncludesCloseButtonWhenVisible() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(promoView.totalBoundsSize, CGSize(width: 240, height: 80))
        XCTAssertEqual(promoView.closeButtonOffset, .zero)

        promoView.showCloseButton = true
        promoView.layoutIfNeeded()

        XCTAssertGreaterThan(promoView.totalBoundsSize.width, 240)
        XCTAssertGreaterThan(promoView.totalBoundsSize.height, 80)
        XCTAssertGreaterThan(promoView.closeButtonOffset.width, 0)
        XCTAssertGreaterThan(promoView.closeButtonOffset.height, 0)

        promoView.closeButtonSpacing = CGSize(width: 12, height: 9)
        promoView.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(promoView.closeButtonOffset.width, 12)
        XCTAssertGreaterThanOrEqual(promoView.closeButtonOffset.height, 9)
    }

    func testCloseButtonSizeChangeReconfiguresButton() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promoView.showCloseButton = true
        promoView.layoutIfNeeded()

        guard let closeButton = promoView.subviews.compactMap({ $0 as? UIButton }).first else {
            return XCTFail("Close button should be present after enabling showCloseButton")
        }
        let smallSize = closeButton.bounds.size

        promoView.closeButtonSize = .large
        promoView.layoutIfNeeded()

        XCTAssertGreaterThan(closeButton.bounds.width, smallSize.width,
                             "Switching to .large should produce a wider button")
    }

    func testProviderConfigurationRoundTripsThroughCoordinator() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        promoView.providerRetryInterval = 17
        promoView.providerFetchTimeout = 9
        promoView.cornerRadius = 12

        XCTAssertEqual(promoView.providerRetryInterval, 17)
        XCTAssertEqual(promoView.providerFetchTimeout, 9)
        XCTAssertEqual(promoView.cornerRadius, 12)
        XCTAssertEqual(promoView.backgroundView.layer.cornerRadius, 12)
    }

    func testContentPaddingReflectsDisplayedContentFrame() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = TestPromoProvider(result: .contentAvailable)
        let padding = UIEdgeInsets(top: 5, left: 6, bottom: 7, right: 8)
        promoView.defaultContentPadding = padding

        XCTAssertEqual(promoView.contentPadding, .zero)

        promoView.currentProvider = provider
        promoView.reloadContentView()
        promoView.layoutIfNeeded()

        XCTAssertEqual(promoView.contentPadding.top, padding.top)
        XCTAssertEqual(promoView.contentPadding.left, padding.left)
        XCTAssertEqual(promoView.contentPadding.bottom, padding.bottom)
        XCTAssertEqual(promoView.contentPadding.right, padding.right)
    }

    func testIsLoadingPropertyDrivesSpinnerVisibility() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 120))
        promoView.backgroundView.backgroundColor = .clear

        promoView.isLoading = true
        promoView.layoutIfNeeded()

        let spinner = promoView.subviews.compactMap { $0 as? UIActivityIndicatorView }.first
        XCTAssertTrue(promoView.isLoading)
        XCTAssertNotNil(spinner)
        XCTAssertFalse(spinner?.isHidden ?? true)

        promoView.isLoading = false

        XCTAssertFalse(promoView.isLoading)
        XCTAssertTrue(spinner?.isHidden ?? false)
    }

    func testTapInteractionLifecycleHandlesEmptyTouchSetsAndCancellation() {
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsEnabled) }

        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        promoView.touchesBegan([], with: nil)
        promoView.touchesMoved([], with: nil)
        promoView.touchesEnded([], with: nil)

        promoView.cancelTapInteraction(animated: false)
        promoView.touchesCancelled([], with: nil)

        promoView.isLoading = true
        promoView.touchesBegan([], with: nil)
        promoView.isLoading = false
        promoView.touchesEnded([], with: nil)

        XCTAssertFalse(promoView.isLoading)
    }
}
