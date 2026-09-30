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

    func testAnimationOptOutPreservesDragCallbacksAndCancellation() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = AnimationBlockingPromoProvider()
        promoView.currentProvider = provider
        let touch = FakeTouch(location: CGPoint(x: 20, y: 20))

        promoView.touchesBegan([touch], with: nil)
        touch.location = CGPoint(x: 300, y: 20)
        promoView.touchesMoved([touch], with: nil)
        touch.location = CGPoint(x: 50, y: 20)
        promoView.touchesMoved([touch], with: nil)
        XCTAssertEqual(provider.dragInsideCount, 2)
        XCTAssertEqual(promoView.backgroundView.superview?.transform, .identity,
                       "Drag callbacks must not re-enable the opted-out press animation")
        promoView.touchesEnded([touch], with: nil)
        XCTAssertEqual(provider.tapUpCount, 1)

        promoView.touchesBegan([touch], with: nil)
        promoView.cancelTapInteraction()
        promoView.touchesMoved([touch], with: nil)
        promoView.touchesEnded([touch], with: nil)
        XCTAssertEqual(provider.dragInsideCount, 2, "Explicit cancellation still suppresses dragging")
        XCTAssertEqual(provider.tapUpCount, 1)
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
    private(set) var dragInsideCount = 0
    private(set) var tapUpCount = 0

    func didDragInside(promoView: PromoView, with touch: UITouch) {
        dragInsideCount += 1
    }

    func didTapUpInside(promoView: PromoView, with touch: UITouch) {
        tapUpCount += 1
    }

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


extension PromoViewDisplayTests {
    func testInitialAnimationOptOutBeforeProvidersAreAssigned() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
        promo.animatesInitialLoadingState = false
        promo.providers = [TestPromoProvider(result: .contentAvailable, showsLoadingIndicatorDuringFetch: true, completes: false)]
        controller.view.addSubview(promo)
        let spinner = promo.subviews.compactMap { $0 as? UIActivityIndicatorView }.first
        let keys = spinner?.layer.animationKeys() ?? []
        XCTAssertTrue(keys.isEmpty, "Initial loading animation is disabled, but spinner has animations: \(keys)")
    }
}


extension PromoViewDisplayTests {
    func testHiddenPromoDoesNotInterceptCloseButtonTouches() throws {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let promo = PromoView(frame: CGRect(x: 20, y: 100, width: 240, height: 80))
        parent.addSubview(promo)
        promo.showCloseButton = true
        promo.layoutIfNeeded()
        let close = try XCTUnwrap(promo.subviews.compactMap { $0 as? UIButton }.first)
        let point = promo.convert(CGPoint(x: close.frame.midX, y: close.frame.midY), to: parent)
        promo.isHidden = true
        XCTAssertTrue(parent.hitTest(point, with: nil) === parent, "An invisible promo must not capture the close button hit area")
    }
}


extension PromoViewDisplayTests {
    func testDraggingOutsideDoesNotReportTapUpInside() {
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = TouchTrackingPromoProvider()
        view.currentProvider = provider
        let touch = FakeTouch(location: CGPoint(x: 20, y: 20))
        view.touchesBegan([touch], with: nil)
        touch.location = CGPoint(x: 500, y: 500)
        view.touchesMoved([touch], with: nil)
        view.touchesEnded([touch], with: nil)
        XCTAssertEqual(provider.tapUpCount, 0, "Dragging away must cancel activation rather than invoke didTapUpInside")
        XCTAssertEqual(provider.cancelTapCount, 1)
    }
}


extension PromoViewDisplayTests {
    func testProviderBackgroundColorIsApplied() {
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promo.delegate = delegate
        promo.providers = [AuditStyledProvider()]
        wait(for: [delegate.updateExpectation], timeout: 1)
        XCTAssertEqual(promo.backgroundView.backgroundColor, UIColor.red, "The provider protocol's backgroundColor must be honoured")
    }
}

private final class AuditStyledProvider: NSObject, PromoProvider {
    var backgroundColor: UIColor? { .red }
    func cornerRadius(for promoView: PromoView, with contentPadding: UIEdgeInsets) -> CGFloat { 30 }
    func fetchNewContent(for promoView: PromoView, with resultHandler: @escaping PromoProviderContentFetchHandler) { resultHandler(.contentAvailable) }
    func contentView(for promoView: PromoView) -> PromoContentView { promoView.dequeueContentView(for: TestPromoContentView.self) }
}

extension PromoViewDisplayTests {
    func testProviderBackgroundColorRestoresHostDefault() {
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promo.backgroundView.backgroundColor = .blue
        let first = PromoViewDelegateSpy()
        promo.delegate = first
        promo.providers = [AuditStyledProvider()]
        wait(for: [first.updateExpectation], timeout: 1)
        XCTAssertEqual(promo.backgroundView.backgroundColor, .red)
        let second = PromoViewDelegateSpy()
        promo.delegate = second
        promo.providers = [TestPromoProvider(result: .contentAvailable)]
        wait(for: [second.updateExpectation], timeout: 1)
        XCTAssertEqual(promo.backgroundView.backgroundColor, .blue)
    }
}


extension PromoViewDisplayTests {
    func testDefaultCornerRadiusRestoredAfterProviderSwap() {
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promo.cornerRadius = 12
        let firstDelegate = PromoViewDelegateSpy()
        promo.delegate = firstDelegate
        promo.providers = [AuditStyledProvider()]
        wait(for: [firstDelegate.updateExpectation], timeout: 1)
        promo.layoutIfNeeded()
        XCTAssertEqual(promo.cornerRadius, 30)
        let secondDelegate = PromoViewDelegateSpy()
        promo.delegate = secondDelegate
        promo.providers = [TestPromoProvider(result: .contentAvailable)]
        wait(for: [secondDelegate.updateExpectation], timeout: 1)
        promo.layoutIfNeeded()
        XCTAssertEqual(promo.cornerRadius, 12, "A provider override must not replace the host's default corner radius")
    }
}

// The close button sits beside the promo view when the superview leaves room to its
// right, and above its top-right corner when it does not. Shrinking a window moved
// it above correctly; widening the window again left it stranded there.
@MainActor
final class PromoViewCloseButtonPlacementTests: XCTestCase {

    private func makeHosted(containerWidth: CGFloat,
                            promoFrame: CGRect) -> (UIView, PromoView, UIButton)? {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: containerWidth, height: 200))
        let promoView = PromoView(frame: promoFrame)
        promoView.showCloseButton = true
        container.addSubview(promoView)
        container.layoutIfNeeded()
        guard let button = promoView.subviews.compactMap({ $0 as? UIButton }).first else { return nil }
        return (container, promoView, button)
    }

    /// Beside means starting past the promo view's trailing edge; above means sitting
    /// at a negative y, over its top-right corner.
    private func isBeside(_ button: UIButton, _ promoView: PromoView) -> Bool {
        button.frame.minX >= promoView.bounds.maxX && button.frame.minY >= 0
    }

    func testCloseButtonSitsBesideWhenThereIsRoom() throws {
        let (_, promoView, button) = try XCTUnwrap(
            makeHosted(containerWidth: 600, promoFrame: CGRect(x: 40, y: 20, width: 460, height: 60)))
        XCTAssertTrue(isBeside(button, promoView))
    }

    func testCloseButtonMovesAboveWhenRoomRunsOut() throws {
        let (_, promoView, button) = try XCTUnwrap(
            makeHosted(containerWidth: 340, promoFrame: CGRect(x: 10, y: 20, width: 320, height: 50)))
        XCTAssertFalse(isBeside(button, promoView))
        XCTAssertLessThan(button.frame.minY, 0, "should sit above the promo view")
    }

    func testCloseButtonReturnsBesideWhenRoomComesBack() throws {
        // The reported bug: narrow the window, then widen it again.
        let (container, promoView, button) = try XCTUnwrap(
            makeHosted(containerWidth: 600, promoFrame: CGRect(x: 40, y: 20, width: 460, height: 60)))
        XCTAssertTrue(isBeside(button, promoView), "precondition: starts beside")

        container.frame.size.width = 340
        promoView.frame = CGRect(x: 10, y: 20, width: 320, height: 50)
        container.layoutIfNeeded()
        XCTAssertFalse(isBeside(button, promoView), "should have moved above while narrow")

        container.frame.size.width = 600
        promoView.frame = CGRect(x: 40, y: 20, width: 460, height: 60)
        container.layoutIfNeeded()
        XCTAssertTrue(isBeside(button, promoView),
                      "close button stayed above after the window was restored")
    }
}

extension PromoViewDisplayTests {
    func testProviderReplacementDuringPressDoesNotActivateReplacement() {
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let original = TouchTrackingPromoProvider()
        let replacement = TouchTrackingPromoProvider()
        let firstDelegate = PromoViewDelegateSpy()
        view.delegate = firstDelegate
        view.providers = [original]
        wait(for: [firstDelegate.updateExpectation], timeout: 1.0)

        let touch = FakeTouch(location: CGPoint(x: 1, y: 1))
        view.touchesBegan([touch], with: nil)
        XCTAssertEqual(original.tapDownCount, 1)

        let replacementDelegate = PromoViewDelegateSpy()
        view.delegate = replacementDelegate
        view.providers = [replacement]
        wait(for: [replacementDelegate.updateExpectation], timeout: 1.0)
        view.touchesMoved([touch], with: nil)
        view.touchesEnded([touch], with: nil)

        XCTAssertEqual(replacement.dragInsideCount, 0)
        XCTAssertEqual(replacement.tapDownCount, 0)
        XCTAssertEqual(replacement.tapUpCount, 0,
                       "A promo loaded while the finger is down must not receive activation from the old promo's press")
        XCTAssertEqual(original.tapUpCount, 0)
        XCTAssertEqual(original.cancelTapCount, 1, "The original provider must release its press state")
    }
}

extension PromoViewDisplayTests {
    func testReplacingContentForTheSameProviderCancelsAnExistingPress() {
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = TouchTrackingPromoProvider()
        view.currentProvider = provider
        view.reloadContentView()
        let touch = FakeTouch(location: CGPoint(x: 1, y: 1))
        view.touchesBegan([touch], with: nil)

        view.reloadContentView()
        view.touchesEnded([touch], with: nil)

        XCTAssertEqual(provider.tapDownCount, 1)
        XCTAssertEqual(provider.tapUpCount, 0, "A replacement creative needs its own new press")
        XCTAssertEqual(provider.cancelTapCount, 1)
    }
}
