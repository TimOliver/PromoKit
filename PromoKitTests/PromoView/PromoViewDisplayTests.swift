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

    func testCloseButtonCanBeHiddenAfterCreation() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promoView.showCloseButton = true
        promoView.layoutIfNeeded()

        guard let closeButton = promoView.subviews.compactMap({ $0 as? UIButton }).first else {
            return XCTFail("Close button should be present after enabling showCloseButton")
        }

        promoView.showCloseButton = false

        XCTAssertTrue(closeButton.isHidden)
        XCTAssertEqual(promoView.closeButtonOffset, .zero)
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

    func testTapInteractionForwardsTouchLifecycleToProvider() {
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsEnabled) }

        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = TouchTrackingPromoProvider()
        let touch = FakeTouch(location: CGPoint(x: 20, y: 20))
        promoView.currentProvider = provider

        promoView.touchesBegan([touch], with: nil)
        touch.location = CGPoint(x: 40, y: 40)
        promoView.touchesMoved([touch], with: nil)
        promoView.touchesEnded([touch], with: nil)

        promoView.touchesBegan([touch], with: nil)
        promoView.touchesCancelled([touch], with: nil)

        XCTAssertEqual(provider.tapDownCount, 2)
        XCTAssertEqual(provider.dragInsideCount, 1)
        XCTAssertEqual(provider.tapUpCount, 1)
        XCTAssertEqual(provider.cancelTapCount, 1)
    }

    func testProviderCanDisableTapInteractionAnimation() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = AnimationBlockingPromoProvider()
        promoView.currentProvider = provider

        promoView.touchesBegan([FakeTouch(location: CGPoint(x: 10, y: 10))], with: nil)

        XCTAssertEqual(provider.animationDecisionCount, 1)
    }
}

private final class FakeTouch: UITouch {
    var location: CGPoint

    init(location: CGPoint) {
        self.location = location
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        location
    }
}

private final class TouchTrackingPromoProvider: NSObject, PromoProvider {
    private(set) var tapDownCount = 0
    private(set) var dragInsideCount = 0
    private(set) var tapUpCount = 0
    private(set) var cancelTapCount = 0

    func fetchNewContent(for promoView: PromoView,
                         with resultHandler: @escaping PromoProviderContentFetchHandler) {
        resultHandler(.contentAvailable)
    }

    func contentView(for promoView: PromoView) -> PromoContentView {
        promoView.dequeueContentView(for: TestPromoContentView.self)
    }

    func didTapDownInside(promoView: PromoView, with touch: UITouch) {
        tapDownCount += 1
    }

    func didDragInside(promoView: PromoView, with touch: UITouch) {
        dragInsideCount += 1
    }

    func didTapUpInside(promoView: PromoView, with touch: UITouch) {
        tapUpCount += 1
    }

    func didCancelTap(promoView: PromoView, with touch: UITouch) {
        cancelTapCount += 1
    }
}

private final class AnimationBlockingPromoProvider: NSObject, PromoProvider {
    private(set) var animationDecisionCount = 0

    func fetchNewContent(for promoView: PromoView,
                         with resultHandler: @escaping PromoProviderContentFetchHandler) {
        resultHandler(.contentAvailable)
    }

    func contentView(for promoView: PromoView) -> PromoContentView {
        promoView.dequeueContentView(for: TestPromoContentView.self)
    }

    func shouldPlayInteractionAnimation(for promoView: PromoView, with touch: UITouch) -> Bool {
        animationDecisionCount += 1
        return false
    }
}
