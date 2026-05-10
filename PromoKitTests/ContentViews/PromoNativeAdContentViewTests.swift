import XCTest
import UIKit
import GoogleMobileAds
@testable import PromoKit
@testable import PromoKitGoogleAds

@MainActor
final class PromoNativeAdContentViewTests: XCTestCase {

    func testNativeProviderStaticConfigurationAndContentView() {
        let provider = PromoNativeAdProvider(adUnitID: "test-native")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))

        provider.didMoveToPromoView(promoView)

        XCTAssertTrue(provider.isInternetAccessRequired)
        XCTAssertEqual(provider.preferredContentSize(fittingSize: CGSize(width: 300, height: 300),
                                                     for: promoView),
                       CGSize(width: 85, height: 85))
        XCTAssertEqual(provider.cornerRadius(for: promoView, with: .zero), 30)
        XCTAssertEqual(provider.contentPadding(for: promoView),
                       UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15))

        let contentView = provider.contentView(for: promoView)
        guard let nativeContentView = contentView as? PromoNativeAdContentView else {
            return XCTFail("Native ads should render through PromoNativeAdContentView")
        }
        XCTAssertNil(nativeContentView.nativeAd)
        XCTAssertNil(nativeContentView.mediaBackgroundImage)
    }

    func testNativeProviderFailureDelegateResolvesFetchFailure() {
        let provider = PromoNativeAdProvider(adUnitID: "test-native")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let failed = expectation(description: "Native ad failure resolves fetch failure")

        provider.fetchNewContent(for: promoView) { result in
            XCTAssertEqual(result, .fetchRequestFailed)
            failed.fulfill()
        }

        let loader = AdLoader(adUnitID: "test-native",
                              rootViewController: nil,
                              adTypes: [.native],
                              options: nil)
        provider.adLoader(loader,
                          didFailToReceiveAdWithError: NSError(domain: "PromoKitTests", code: 1))

        wait(for: [failed], timeout: 1.0)
    }

    func testNativeProviderInteractionAnimationRequiresTouchInsideContentView() {
        let provider = PromoNativeAdProvider(adUnitID: "test-native")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))

        XCTAssertFalse(provider.shouldPlayInteractionAnimation(for: promoView,
                                                               with: FakeTouch(location: CGPoint(x: 20, y: 20))))

        let contentView = PromoNativeAdContentView(promoView: promoView)
        contentView.frame = CGRect(x: 40, y: 40, width: 120, height: 120)
        promoView.contentView = contentView

        XCTAssertFalse(provider.shouldPlayInteractionAnimation(for: promoView,
                                                               with: FakeTouch(location: CGPoint(x: 20, y: 20))))
        XCTAssertTrue(provider.shouldPlayInteractionAnimation(for: promoView,
                                                              with: FakeTouch(location: CGPoint(x: 80, y: 80))))
    }

    func testNativeProviderTouchLifecycleResetsTapTracking() {
        let provider = PromoNativeAdProvider(adUnitID: "test-native")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let contentView = PromoNativeAdContentView(promoView: promoView)
        contentView.frame = CGRect(x: 0, y: 0, width: 220, height: 220)
        promoView.contentView = contentView
        provider.didMoveToPromoView(promoView)

        provider.didTapDownInside(promoView: promoView, with: FakeTouch(location: CGPoint(x: 60, y: 60)))
        provider.didDragInside(promoView: promoView, with: FakeTouch(location: CGPoint(x: 70, y: 70)))
        provider.didTapUpInside(promoView: promoView, with: FakeTouch(location: CGPoint(x: 70, y: 70)))

        provider.didTapDownInside(promoView: promoView, with: FakeTouch(location: CGPoint(x: 60, y: 60)))
        provider.didDragInside(promoView: promoView, with: FakeTouch(location: CGPoint(x: 140, y: 60)))
        provider.didCancelTap(promoView: promoView, with: FakeTouch(location: CGPoint(x: 140, y: 60)))

        XCTAssertTrue(provider.shouldPlayInteractionAnimation(for: promoView,
                                                              with: FakeTouch(location: CGPoint(x: 60, y: 60))))
    }

    func testNativeProviderReceivesFakeNativeAdAndPublishesBlurredImage() {
        let provider = PromoNativeAdProvider(adUnitID: "test-native")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let loader = AdLoader(adUnitID: "test-native",
                              rootViewController: nil,
                              adTypes: [.native],
                              options: nil)
        let image = makePromoTestImage(size: CGSize(width: 80, height: 80), color: .systemPink)
        let nativeAd = FakeNativeAd(aspectRatio: 1.0,
                                    headline: "Test mode: Promo",
                                    body: "Body",
                                    callToAction: "install",
                                    images: [NativeAdImage(image: image)])
        provider.didMoveToPromoView(promoView)

        provider.adLoader(loader, didReceive: nativeAd)
        waitForBackgroundQueueToDrain(promoView)

        let contentView = provider.contentView(for: promoView)
        guard let nativeContentView = contentView as? PromoNativeAdContentView else {
            return XCTFail("Provider should vend a native ad content view")
        }

        XCTAssertTrue(nativeContentView.nativeAd === nativeAd)
        XCTAssertNotNil(nativeContentView.mediaBackgroundImage)

        provider.adLoader(loader, didReceive: nativeAd)
    }

    func testNativeContentViewBackgroundSizingAndReuse() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        promoView.backgroundView.backgroundColor = .systemPurple
        let contentView = PromoNativeAdContentView(promoView: promoView)
        let backgroundImage = makePromoTestImage(size: CGSize(width: 12, height: 12), color: .purple)

        XCTAssertTrue(contentView.wantsSizingControl)
        XCTAssertEqual(contentView.adChoicesViewFrame, .zero)

        contentView.mediaBackgroundImage = backgroundImage
        contentView.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        contentView.layoutIfNeeded()

        XCTAssertNotNil(contentView.mediaBackgroundImage)
        XCTAssertEqual(contentView.sizeThatFits(CGSize(width: 300, height: 300)), .zero)

        contentView.prepareForReuse()

        XCTAssertNil(contentView.nativeAd)
        XCTAssertNil(contentView.mediaBackgroundImage)
    }

    func testNativeAdViewLaysOutPortraitAdWithStorePriceFallback() {
        let adView = PromoNativeAdView()
        let icon = makePromoTestImage(size: CGSize(width: 40, height: 40), color: .green)
        let nativeAd = FakeNativeAd(aspectRatio: 1.4,
                                    headline: "Test mode: Great App",
                                    body: nil,
                                    store: "App Store",
                                    price: "$1.99",
                                    callToAction: "open",
                                    icon: NativeAdImage(image: icon))

        adView.backgroundColor = .white
        adView.configureContentViews(with: nativeAd)
        adView.frame = CGRect(origin: .zero, size: CGSize(width: 360, height: 420))
        adView.layoutIfNeeded()

        XCTAssertGreaterThan(adView.sizeThatFits(CGSize(width: 360, height: 420)).height, 0)
        XCTAssertNotNil(adView.headlineView)
        XCTAssertNotNil(adView.bodyView)
        XCTAssertNotNil(adView.iconView)
        XCTAssertNotNil(adView.mediaView)
        XCTAssertNotNil(adView.callToActionView)
    }

    func testNativeAdViewLaysOutCompactLandscapeAd() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("traitOverrides is needed to force compact vertical size class")
        }

        let adView = PromoNativeAdView()
        let icon = makePromoTestImage(size: CGSize(width: 48, height: 48), color: .cyan)
        let nativeAd = FakeNativeAd(aspectRatio: 0.5,
                                    headline: "Test mode: Tall Creative",
                                    body: "Compact body",
                                    callToAction: "learn more",
                                    icon: NativeAdImage(image: icon))

        adView.traitOverrides.verticalSizeClass = .compact
        adView.backgroundColor = .white
        adView.configureContentViews(with: nativeAd)
        adView.frame = CGRect(origin: .zero, size: CGSize(width: 500, height: 180))
        adView.layoutIfNeeded()

        let fittingSize = adView.sizeThatFits(CGSize(width: 500, height: 180))
        XCTAssertGreaterThan(fittingSize.width, 0)
        XCTAssertGreaterThan(fittingSize.height, 0)
        XCTAssertLessThanOrEqual(fittingSize.height, 180)
        XCTAssertNotNil(adView.headlineView)
        XCTAssertNotNil(adView.bodyView)
        XCTAssertNotNil(adView.iconView)
        XCTAssertNotNil(adView.mediaView)
        XCTAssertNotNil(adView.callToActionView)
    }

    func testNativeAdViewResetAndActionButtonLayout() {
        let adView = PromoNativeAdView()
        let backgroundImage = makePromoTestImage(size: CGSize(width: 12, height: 12), color: .blue)

        adView.mediaBackgroundImage = backgroundImage
        XCTAssertNotNil(adView.mediaBackgroundImage)

        adView.reset()
        XCTAssertNil(adView.mediaBackgroundImage)

        let button = PromoNativeAdActionButton(frame: CGRect(x: 0, y: 0, width: 120, height: 40))
        button.title = "Install"
        button.tintColor = .systemGreen
        button.layoutIfNeeded()

        XCTAssertEqual(button.title, "Install")
        XCTAssertEqual(button.layer.cornerRadius, 20)

        if #available(iOS 26.0, *) {
            let glassView = button.subviews.compactMap { $0 as? UIVisualEffectView }.first
            XCTAssertEqual(glassView?.frame, button.bounds)
            XCTAssertEqual((glassView?.effect as? UIGlassEffect)?.tintColor, .systemGreen)
        }
    }

    private func waitForBackgroundQueueToDrain(_ promoView: PromoView) {
        let drained = expectation(description: "Background queue drained")
        promoView.backgroundQueue.addOperation {
            OperationQueue.main.addOperation {
                drained.fulfill()
            }
        }
        wait(for: [drained], timeout: 2.0)
    }
}

private final class FakeTouch: UITouch {
    private let point: CGPoint

    init(location: CGPoint) {
        self.point = location
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        point
    }
}

private final class FakeMediaContent: MediaContent {
    private let fakeAspectRatio: CGFloat

    init(aspectRatio: CGFloat) {
        self.fakeAspectRatio = aspectRatio
        super.init()
    }

    override var aspectRatio: CGFloat { fakeAspectRatio }
}

private final class FakeNativeAd: NativeAd {
    private let fakeHeadline: String?
    private let fakeBody: String?
    private let fakeStore: String?
    private let fakePrice: String?
    private let fakeCallToAction: String?
    private let fakeIcon: NativeAdImage?
    private let fakeImages: [NativeAdImage]?
    private let fakeMediaContent: MediaContent

    init(aspectRatio: CGFloat,
         headline: String?,
         body: String? = nil,
         store: String? = nil,
         price: String? = nil,
         callToAction: String? = nil,
         icon: NativeAdImage? = nil,
         images: [NativeAdImage]? = nil) {
        self.fakeHeadline = headline
        self.fakeBody = body
        self.fakeStore = store
        self.fakePrice = price
        self.fakeCallToAction = callToAction
        self.fakeIcon = icon
        self.fakeImages = images
        self.fakeMediaContent = FakeMediaContent(aspectRatio: aspectRatio)
        super.init()
    }

    override var headline: String? { fakeHeadline }
    override var body: String? { fakeBody }
    override var store: String? { fakeStore }
    override var price: String? { fakePrice }
    override var callToAction: String? { fakeCallToAction }
    override var icon: NativeAdImage? { fakeIcon }
    override var images: [NativeAdImage]? { fakeImages }
    override var mediaContent: MediaContent { fakeMediaContent }
}
