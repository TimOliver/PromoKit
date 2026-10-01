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

        let loader = activeLoader(for: provider)
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
        provider.fetchNewContent(for: promoView) { _ in }
        let loader = activeLoader(for: provider)
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

extension PromoNativeAdContentViewTests {
    func testUnfinishedNativeRequestDoesNotRetainProviderOrHost() throws {
        weak var releasedProvider: PromoNativeAdProvider?
        weak var releasedView: PromoView?
        var retainedLoader: AdLoader?

        try autoreleasepool {
            let provider = PromoNativeAdProvider(adUnitID: "test-native")
            let view = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
            releasedProvider = provider
            releasedView = view
            provider.didMoveToPromoView(view)
            provider.fetchNewContent(for: view) { _ in
                XCTFail("An unfinished request must not deliver a result after teardown")
            }
            let field = try XCTUnwrap(Mirror(reflecting: provider).children.first { $0.label == "adLoader" })
            retainedLoader = try XCTUnwrap(Mirror(reflecting: field.value).children.first?.value as? AdLoader)
            XCTAssertTrue(retainedLoader?.delegate === provider)
        }

        XCTAssertNil(releasedProvider)
        XCTAssertNil(releasedView)
        XCTAssertNil(retainedLoader?.delegate, "The SDK loader may outlive its provider")
        retainedLoader?.delegate = nil
    }

    func testPendingBlurDoesNotRetainProviderOrPublishAfterTeardown() {
        weak var releasedProvider: PromoNativeAdProvider?
        weak var releasedView: PromoView?
        let queue = PromoView(frame: .zero).backgroundQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }

        autoreleasepool {
            let provider = PromoNativeAdProvider(adUnitID: "test-native")
            let view = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
            releasedProvider = provider
            releasedView = view
            provider.didMoveToPromoView(view)
            provider.fetchNewContent(for: view) { _ in
                XCTFail("Abandoned image processing must not publish content")
            }
            let image = makePromoTestImage(size: CGSize(width: 40, height: 40), color: .purple)
            let ad = FakeNativeAd(aspectRatio: 1, headline: "Pending image",
                                  images: [NativeAdImage(image: image)])
            provider.adLoader(activeLoader(for: provider), didReceive: ad)
            XCTAssertGreaterThan(queue.operationCount, 0)
        }

        XCTAssertNil(releasedProvider, "Suspended background work must not extend the provider's lifetime")
        XCTAssertNil(releasedView)
        queue.isSuspended = false
        queue.waitUntilAllOperationsAreFinished()
        let drained = expectation(description: "Abandoned blur's main-queue callback drains")
        OperationQueue.main.addOperation { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    func testActiveTapTimerIsInvalidatedWhenProviderIsReleased() throws {
        weak var releasedProvider: PromoNativeAdProvider?
        weak var releasedView: PromoView?
        var retainedTimer: Timer?

        try autoreleasepool {
            let provider = PromoNativeAdProvider(adUnitID: "test-native")
            let view = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
            let content = PromoNativeAdContentView(promoView: view)
            content.frame = view.bounds
            view.contentView = content
            provider.didMoveToPromoView(view)
            releasedProvider = provider
            releasedView = view
            provider.didTapDownInside(promoView: view, with: FakeTouch(location: CGPoint(x: 50, y: 50)))
            let field = try XCTUnwrap(Mirror(reflecting: provider).children.first { $0.label == "tapDownTimer" })
            retainedTimer = try XCTUnwrap(Mirror(reflecting: field.value).children.first?.value as? Timer)
            XCTAssertTrue(retainedTimer?.isValid == true)
        }

        XCTAssertNil(releasedProvider)
        XCTAssertNil(releasedView)
        XCTAssertFalse(retainedTimer?.isValid == true, "Teardown must invalidate the run-loop's pending timer")
        retainedTimer?.invalidate()
    }
}

private final class FakeMediaContent: MediaContent {
    var fakeAspectRatio: CGFloat
    let fakeVideoController = FakeVideoController()

    init(aspectRatio: CGFloat) {
        self.fakeAspectRatio = aspectRatio
        super.init()
    }

    override var aspectRatio: CGFloat { fakeAspectRatio }
    override var videoController: VideoController { fakeVideoController }
}

private final class FakeVideoController: VideoController {
    func simulatePlay() {
        delegate?.videoControllerDidPlayVideo?(self)
    }
}

private final class FakeNativeAd: NativeAd {
    private let fakeHeadline: String?
    private let fakeBody: String?
    private let fakeStore: String?
    private let fakePrice: String?
    private let fakeCallToAction: String?
    private let fakeIcon: NativeAdImage?
    private let fakeImages: [NativeAdImage]?
    private let fakeMediaContent: FakeMediaContent

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

    var reportedAspectRatio: CGFloat {
        get { fakeMediaContent.fakeAspectRatio }
        set { fakeMediaContent.fakeAspectRatio = newValue }
    }

    var videoController: FakeVideoController { fakeMediaContent.fakeVideoController }
}


extension PromoNativeAdContentViewTests {
    func testReuseClearsGoogleNativeAdRegistration() throws {
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 360, height: 420))
        let content = PromoNativeAdContentView(promoView: promo)
        let nativeAd = FakeNativeAd(aspectRatio: 1.4, headline: "Old creative", callToAction: "Install")
        content.nativeAd = nativeAd
        let inner = try XCTUnwrap(content.subviews.compactMap { $0 as? PromoNativeAdView }.first)
        XCTAssertNotNil(inner.nativeAd)
        XCTAssertTrue(nativeAd.videoController.delegate === inner)
        content.prepareForReuse()
        XCTAssertNil(inner.nativeAd, "The SDK ad registration must be cleared when returning a view to the pool")
        XCTAssertNil(nativeAd.videoController.delegate)
    }
}


extension PromoNativeAdContentViewTests {
    func testOldBlurDoesNotCompleteReplacementRequest() {
        let provider = PromoNativeAdProvider(adUnitID: "audit-native")
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 360, height: 420))
        provider.didMoveToPromoView(promo)
        promo.backgroundQueue.isSuspended = true
        defer { promo.backgroundQueue.isSuspended = false }
        provider.fetchNewContent(for: promo) { _ in }
        let loaderField = Mirror(reflecting: provider).children.first { $0.label == "adLoader" }!.value
        let loader = Mirror(reflecting: loaderField).children.first!.value as! AdLoader
        loader.delegate = nil // Hold SDK completion; deliver the old successful load below.
        let oldImage = makePromoTestImage(size: CGSize(width: 40, height: 40), color: .red)
        provider.adLoader(loader, didReceive: FakeNativeAd(aspectRatio: 1, headline: "Old request", images: [NativeAdImage(image: oldImage)]))
        var replacementResults: [PromoProviderFetchContentResult] = []
        provider.fetchNewContent(for: promo) { replacementResults.append($0) }
        let replacementField = Mirror(reflecting: provider).children.first { $0.label == "adLoader" }!.value
        let replacementLoader = Mirror(reflecting: replacementField).children.first!.value as! AdLoader
        replacementLoader.delegate = nil // The replacement request is still outstanding.
        promo.backgroundQueue.isSuspended = false
        waitForBackgroundQueueToDrain(promo)
        XCTAssertFalse(replacementResults.contains(.contentAvailable), "Old image processing must not resolve a new request with old content")
    }
}

extension PromoNativeAdContentViewTests {
    /// Hold SDK responses so delegate outcomes can be delivered deterministically.
    private func activeLoader(for provider: PromoNativeAdProvider) -> AdLoader {
        let field = Mirror(reflecting: provider).children.first { $0.label == "adLoader" }!.value
        let loader = Mirror(reflecting: field).children.first!.value as! AdLoader
        loader.delegate = nil
        return loader
    }

    func testStaleNativeLoaderCannotCompleteReplacementRequest() {
        let provider = PromoNativeAdProvider(adUnitID: "test-native")
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        provider.fetchNewContent(for: view) { _ in XCTFail("Old request should be superseded") }
        let oldLoader = activeLoader(for: provider)
        var results: [PromoProviderFetchContentResult] = []
        provider.fetchNewContent(for: view) { results.append($0) }
        let newLoader = activeLoader(for: provider)
        provider.adLoader(oldLoader, didFailToReceiveAdWithError: NSError(domain: "test", code: 1))
        XCTAssertTrue(results.isEmpty)
        provider.adLoader(newLoader, didFailToReceiveAdWithError: NSError(domain: "test", code: 1))
        XCTAssertEqual(results, [.fetchRequestFailed])
    }
}


extension PromoNativeAdContentViewTests {
    func testNoImageCreativeDoesNotKeepPreviousBackground() {
        let provider = PromoNativeAdProvider(adUnitID: "audit-native")
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 360, height: 420))
        provider.didMoveToPromoView(promo)
        provider.fetchNewContent(for: promo) { _ in }
        let loader = activeLoader(for: provider)
        let image = makePromoTestImage(size: CGSize(width: 40, height: 40), color: .red)
        provider.adLoader(loader, didReceive: FakeNativeAd(aspectRatio: 1, headline: "Old image", images: [NativeAdImage(image: image)]))
        waitForBackgroundQueueToDrain(promo)
        provider.fetchNewContent(for: promo) { _ in }
        let nextLoader = activeLoader(for: provider)
        provider.adLoader(nextLoader, didReceive: FakeNativeAd(aspectRatio: 1, headline: "New image-free creative"))
        let content = provider.contentView(for: promo) as? PromoNativeAdContentView
        XCTAssertNil(content?.mediaBackgroundImage, "New creative must not display the previous advertiser's background")
    }
}

// A portrait creative in a wide container used to be laid out stacked: the media
// container kept the card's full width while the video, fitted to the container's
// height, only needed a fraction of it. The rest became blurred backdrop — on a
// landscape iPad, roughly two thirds of the media area.
//
// The side-by-side layout that solves this already existed, but was gated on
// `verticalSizeClass == .compact`, which asks about the device rather than the box.
// An iPad is always regular height, so it never qualified no matter how wide it got.
// These cover the geometry that replaced that check.
@MainActor
final class PromoNativeAdLayoutGeometryTests: XCTestCase {

    private let portraitAspect: CGFloat = 9.0 / 16.0
    private let minimumColumn: CGFloat = 240.0
    private let maximumFraction: CGFloat = 0.55

    private func format(_ size: CGSize, aspect: CGFloat) -> PromoNativeAdView.LayoutFormat {
        PromoNativeAdView.layoutFormat(containerSize: size,
                                              mediaAspectRatio: aspect,
                                              minimumTextColumnWidth: minimumColumn,
                                              maximumMediaWidthFraction: maximumFraction)
    }

    private func media(_ size: CGSize, aspect: CGFloat) -> CGSize {
        PromoNativeAdView.mediaSize(fitting: size,
                                           aspectRatio: aspect,
                                           maximumWidthFraction: maximumFraction)
    }

    // MARK: - Choosing a format

    func testPhonePortraitStaysStacked() {
        // The video very nearly fills the width; there is no column to move text into.
        XCTAssertEqual(format(CGSize(width: 360, height: 600), aspect: portraitAspect), .stacked)
    }

    func testPhoneLandscapeGoesSideBySide() {
        // Already the behaviour today, via the compact-height check. It must survive
        // the move to geometry, or this fix regresses the one case that worked.
        XCTAssertEqual(format(CGSize(width: 700, height: 300), aspect: portraitAspect), .sideBySide)
    }

    func testLandscapeIPadGoesSideBySide() {
        // The case that motivated all of this: ~636pt of video leaves ~974pt of column.
        XCTAssertEqual(format(CGSize(width: 1610, height: 1130), aspect: portraitAspect), .sideBySide)
    }

    func testLandscapeCreativeStaysStacked() {
        // A wide creative already fills the card's width with no wasted space, so
        // stacking it is right regardless of how much room is going spare.
        XCTAssertEqual(format(CGSize(width: 1610, height: 1130), aspect: 16.0 / 9.0), .stacked)
    }

    func testUnusableAspectRatioStaysStacked() {
        // Google reports 0 before the media content resolves. Fail back to the layout
        // that works without knowing the shape rather than dividing by it.
        XCTAssertEqual(format(CGSize(width: 1610, height: 1130), aspect: 0), .stacked)
    }

    // MARK: - Sizing the media

    func testVideoTakesFullHeightWhenItFitsUnderTheCap() {
        // 1130 * (9/16) = 635.6, comfortably under the 885.5 cap.
        let size = media(CGSize(width: 1610, height: 1130), aspect: portraitAspect)
        XCTAssertEqual(size.height, 1130, accuracy: 0.5)
        XCTAssertEqual(size.width, 635.6, accuracy: 0.5)
    }

    func testVideoIsCappedAndLetterboxedWhenItWouldDominate() {
        // 1000 * (9/16) = 562.5 against a 330 cap, so the video yields: it shrinks
        // and gains vertical letterboxing rather than squeezing the text column.
        let size = media(CGSize(width: 600, height: 1000), aspect: portraitAspect)
        XCTAssertEqual(size.width, 330, accuracy: 0.5)
        XCTAssertEqual(size.height, 586.7, accuracy: 0.5)
        XCTAssertLessThan(size.height, 1000)
    }

    func testMediaNeverExceedsTheContainer() {
        let container = CGSize(width: 600, height: 1000)
        let size = media(container, aspect: portraitAspect)
        XCTAssertLessThanOrEqual(size.width, container.width)
        XCTAssertLessThanOrEqual(size.height, container.height)
    }

    func testCapIsAFractionOfWidthNotHeight() {
        // Guards the axis: capping against height would make the rule collapse into
        // the vertical fit that already exists, and the wings would come back.
        let size = media(CGSize(width: 400, height: 2000), aspect: portraitAspect)
        XCTAssertEqual(size.width, 220, accuracy: 0.5)
    }
}

// The card used to be measured at one width and then drawn at another. PromoKit
// budgeted the media band as `width / aspectRatio` against its own 500pt cap, and
// the host then widened the card to its readable-content width without the height
// being recomputed. The band ended up far too short for its width, so the media
// view was stretched wider than the creative and Google's MediaView pillarboxed
// inside it — the grey wings either side of a 16:9 video.
@MainActor
final class PromoNativeAdMediaFitTests: XCTestCase {

    private let landscapeAspect: CGFloat = 16.0 / 9.0
    private let portraitAspect: CGFloat = 9.0 / 16.0

    private func fitted(_ container: CGSize, aspect: CGFloat) -> CGSize {
        PromoNativeAdView.fittedMediaSize(containerSize: container, aspectRatio: aspect)
    }

    // MARK: - Fitting preserves the creative's shape

    func testWideCreativeInAShortBandKeepsItsAspectRatio() {
        // The regression: an 890x281 band for a 16:9 creative. The media view must
        // not take the band's full width, or the creative pillarboxes inside it.
        let size = fitted(CGSize(width: 890, height: 281), aspect: landscapeAspect)
        XCTAssertEqual(size.width / size.height, landscapeAspect, accuracy: 0.01)
        XCTAssertEqual(size.height, 281, accuracy: 0.5)
        XCTAssertLessThan(size.width, 890)
    }

    func testTallCreativeInAWideBandKeepsItsAspectRatio() {
        let size = fitted(CGSize(width: 890, height: 600), aspect: portraitAspect)
        XCTAssertEqual(size.width / size.height, portraitAspect, accuracy: 0.01)
        XCTAssertEqual(size.height, 600, accuracy: 0.5)
    }

    func testCreativeIsNotStretchedToFillABandLargerThanItself() {
        // Scale is capped at 1: a band roomier than the creative leaves space rather
        // than blowing the creative up past its natural size.
        let size = fitted(CGSize(width: 2000, height: 2000), aspect: landscapeAspect)
        XCTAssertEqual(size.width / size.height, landscapeAspect, accuracy: 0.01)
        XCTAssertLessThanOrEqual(size.width, 2000)
        XCTAssertLessThanOrEqual(size.height, 2000)
    }

    func testUnusableAspectRatioYieldsNoMedia() {
        XCTAssertEqual(fitted(CGSize(width: 890, height: 281), aspect: 0), .zero)
    }

    // MARK: - Choosing a width the height can actually pay for

    private func width(_ container: CGSize, aspect: CGFloat, chrome: CGFloat, maximum: CGFloat) -> CGFloat {
        PromoNativeAdView.contentWidth(fitting: container,
                                       aspectRatio: aspect,
                                       chromeHeight: chrome,
                                       maximumWidth: maximum)
    }

    func testWidthIsLimitedByTheHeightLeftForTheBand() {
        // 700pt tall, 200pt of it text and chrome, so the band can be 500 — which at
        // 16:9 pays for 889pt of width. Anything wider would squeeze the band.
        let w = width(CGSize(width: 1100, height: 700), aspect: landscapeAspect, chrome: 200, maximum: 4000)
        XCTAssertEqual(w, 889, accuracy: 1.0)
    }

    func testWidthStillRespectsTheContainerAndTheCap() {
        XCTAssertEqual(width(CGSize(width: 320, height: 700), aspect: landscapeAspect, chrome: 200, maximum: 4000), 320, accuracy: 0.5)
        XCTAssertEqual(width(CGSize(width: 1100, height: 700), aspect: landscapeAspect, chrome: 200, maximum: 500), 500, accuracy: 0.5)
    }

    func testWidthNeverGoesNegativeWhenChromeEatsTheContainer() {
        // A container shorter than its own text: the band gets nothing rather than a
        // negative width that would invert the frame.
        XCTAssertEqual(width(CGSize(width: 1100, height: 120), aspect: landscapeAspect, chrome: 200, maximum: 4000), 0, accuracy: 0.5)
    }
}

// Set beside a tall creative, the text column is far taller than two lines of
// headline and three of body need, so the copy was stranded at the top with the
// call to action pinned to the foot and most of the column empty. The text grows
// into that space instead. A short column — an iPhone in landscape, which is what
// this layout was originally written for — must come out exactly as before.
@MainActor
final class PromoNativeAdTextScaleTests: XCTestCase {

    private let targetFill: CGFloat = 0.5
    private let maximumScale: CGFloat = 2.2

    private func scale(available: CGFloat, natural: CGFloat) -> CGFloat {
        PromoNativeAdView.textScale(availableHeight: available,
                                    naturalHeight: natural,
                                    targetFill: targetFill,
                                    maximumScale: maximumScale)
    }

    func testShortColumnLeavesTheTextAlone() {
        // iPhone landscape: ~200pt of column against ~120pt of text. Scaling here
        // would make the copy bigger than the layout was designed around.
        XCTAssertEqual(scale(available: 200, natural: 120), 1.0, accuracy: 0.01)
    }

    func testTallColumnGrowsTheText() {
        // 550pt of column against ~120pt of text wants 2.29, so the cap applies.
        XCTAssertEqual(scale(available: 550, natural: 120), maximumScale, accuracy: 0.01)
    }

    func testGrowthIsProportionalBelowTheCap() {
        // 300 * 0.5 / 100 = 1.5, comfortably under the cap and used as-is.
        XCTAssertEqual(scale(available: 300, natural: 100), 1.5, accuracy: 0.01)
    }

    func testTextIsNeverScaledDown() {
        // Overflow is already handled further down by the existing shrink-to-fit
        // pass; this one only ever grows, so it must not fight it.
        XCTAssertEqual(scale(available: 100, natural: 400), 1.0, accuracy: 0.01)
    }

    func testUnmeasuredTextIsLeftAlone() {
        XCTAssertEqual(scale(available: 550, natural: 0), 1.0, accuracy: 0.01)
    }
}

// Google's call to action varies wildly by locale — "Install" against
// "今すぐダウンロード" — and the compact pill was a fixed 120pt wide. Shrink-to-fit
// rescues a near miss; it cannot rescue a call to action half again too long, so
// those clipped. The pill now reports the width its own text needs.
@MainActor
final class PromoNativeAdActionButtonWidthTests: XCTestCase {

    private func button(_ title: String) -> PromoNativeAdActionButton {
        let button = PromoNativeAdActionButton(frame: .zero)
        button.title = title
        return button
    }

    func testLongerTitlesAskForMoreWidth() {
        let short = button("Install").widthThatFits(height: 40)
        let long = button("今すぐダウンロードする").widthThatFits(height: 40)
        XCTAssertGreaterThan(long, short)
    }

    func testWidthLeavesRoomForTheRoundedCaps() {
        // The label is inset by half the corner radius at each end, so the pill must
        // ask for more than its bare text or the text runs into the curve.
        let title = "Learn More"
        let height: CGFloat = 40
        let bare = (title as NSString)
            .size(withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18.0)]).width
        XCTAssertGreaterThan(button(title).widthThatFits(height: height), bare)
    }

    func testEmptyTitleStillAsksForAPillShape() {
        XCTAssertEqual(button("").widthThatFits(height: 40), 80)
    }
}

// MARK: - Unknown Creative Shape

extension PromoNativeAdContentViewTests {

    func testAReportedAspectRatioWins() {
        // Authoritative when Google has it, whatever the still says.
        XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: 16.0 / 9.0,
                                                           stillSize: CGSize(width: 100, height: 400)),
                       16.0 / 9.0, accuracy: 0.0001)
    }

    func testTheStillStandsInForAnUnreportedRatio() {
        // An available still gives us an estimate when Google's ratio is unknown.
        XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: 0.0,
                                                           stillSize: CGSize(width: 1080, height: 1920)),
                       1080.0 / 1920.0, accuracy: 0.0001)
    }

    func testASquareIsTheLastResort() {
        // No ratio and no still: a square is the least wrong guess, and crucially
        // not the degenerate full-container one a raw zero produced.
        XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: 0.0, stillSize: nil), 1.0)
    }

    func testADegenerateStillIsIgnored() {
        XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: 0.0,
                                                           stillSize: CGSize(width: 0, height: 100)), 1.0)
        XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: 0.0,
                                                           stillSize: CGSize(width: 100, height: 0)), 1.0)
    }

    func testANegativeReportedRatioFallsThroughToTheStill() {
        XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: -1.5,
                                                           stillSize: CGSize(width: 400, height: 200)),
                       2.0, accuracy: 0.0001)
    }

    func testAnUnknownShapeWithoutAnImageIsPublishedImmediately() {
        let provider = PromoNativeAdProvider(adUnitID: "test-native")
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 360, height: 420))
        provider.didMoveToPromoView(promo)
        var results: [PromoProviderFetchContentResult] = []
        provider.fetchNewContent(for: promo) { results.append($0) }
        let loader = activeLoader(for: provider)
        let nativeAd = FakeNativeAd(aspectRatio: 0, headline: "Unknown shape")

        provider.adLoader(loader, didReceive: nativeAd)

        XCTAssertEqual(results, [.contentAvailable], "An unknown ratio must not defer publication to a timer")
        let content = provider.contentView(for: promo) as? PromoNativeAdContentView
        XCTAssertTrue(content?.nativeAd === nativeAd)
    }

    func testNonfiniteReportedRatiosFallThroughToTheStill() {
        for reported in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: reported,
                                                               stillSize: CGSize(width: 400, height: 200)),
                           2.0)
        }
    }

    func testNonfiniteStillRatiosFallBackToASquare() {
        let stillSizes = [CGSize(width: CGFloat.infinity, height: 100),
                          CGSize(width: 100, height: CGFloat.infinity),
                          CGSize(width: CGFloat.nan, height: 100),
                          CGSize(width: 100, height: CGFloat.nan),
                          CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.leastNonzeroMagnitude)]
        for stillSize in stillSizes {
            XCTAssertEqual(PromoNativeAdView.usableAspectRatio(reported: 0, stillSize: stillSize), 1.0)
        }
    }

    func testVideoPlaybackReplacesTheStillShapeInMeasurementAndLayout() throws {
        let adView = PromoNativeAdView()
        let still = makePromoTestImage(size: CGSize(width: 90, height: 160), color: .blue)
        let nativeAd = FakeNativeAd(aspectRatio: 0,
                                    headline: "Creative",
                                    callToAction: "Install",
                                    images: [NativeAdImage(image: still)])
        var shapeChanges = 0
        adView.mediaAspectRatioDidChange = { shapeChanges += 1 }
        adView.configureContentViews(with: nativeAd)
        let original = try geometry(of: adView)
        XCTAssertEqual(original.mediaFrame.width / original.mediaFrame.height, 9.0 / 16.0, accuracy: 0.01)
        XCTAssertEqual(shapeChanges, 0, "Initial configuration already uses the still's shape")
        XCTAssertTrue(nativeAd.videoController.delegate === adView)

        nativeAd.reportedAspectRatio = 16.0 / 9.0
        nativeAd.videoController.simulatePlay()

        XCTAssertEqual(shapeChanges, 1)
        let playing = try geometry(of: adView)
        XCTAssertNotEqual(playing.fittingSize, original.fittingSize)
        XCTAssertNotEqual(playing.mediaContainerFrame, original.mediaContainerFrame)
        XCTAssertNotEqual(playing.headlineFrame, original.headlineFrame)
        XCTAssertEqual(playing.mediaFrame.width / playing.mediaFrame.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertEqual(shapeChanges, 1, "The subsequent layout must not notify the same change again")

        nativeAd.videoController.simulatePlay()
        XCTAssertEqual(shapeChanges, 1, "Resuming the same video does not change its shape")
    }

    func testLayoutDetectsANewShapeEvenIfItWasAlreadyMeasured() throws {
        let adView = PromoNativeAdView()
        adView.maximumWidth = 900
        adView.maximumHeight = 600
        let nativeAd = FakeNativeAd(aspectRatio: 0, headline: "Creative", callToAction: "Install")
        var shapeChanges = 0
        adView.mediaAspectRatioDidChange = { shapeChanges += 1 }
        adView.configureContentViews(with: nativeAd)
        let original = try geometry(of: adView)

        nativeAd.reportedAspectRatio = 9.0 / 16.0
        let measured = adView.sizeThatFits(CGSize(width: 900, height: 600))

        XCTAssertNotEqual(measured, original.fittingSize)
        XCTAssertEqual(shapeChanges, 0, "Measurement should not call into the host during its sizing pass")
        let updated = try geometry(of: adView)
        XCTAssertEqual(updated.mediaFrame.width / updated.mediaFrame.height, 9.0 / 16.0, accuracy: 0.01)
        XCTAssertEqual(shapeChanges, 1, "Measurement must not consume the change before layout can notify the host")
        _ = try geometry(of: adView)
        XCTAssertEqual(shapeChanges, 1)
    }

    func testRepeatedUnknownRatiosDoNotNotifyShapeChanges() throws {
        let adView = PromoNativeAdView()
        let nativeAd = FakeNativeAd(aspectRatio: 0, headline: "Creative", callToAction: "Install")
        var shapeChanges = 0
        adView.mediaAspectRatioDidChange = { shapeChanges += 1 }
        adView.configureContentViews(with: nativeAd)
        let original = try geometry(of: adView)

        for reported in [CGFloat.zero, .nan, .infinity, -1, 1] {
            nativeAd.reportedAspectRatio = reported
            nativeAd.videoController.simulatePlay()
            XCTAssertEqual(try geometry(of: adView), original)
        }

        XCTAssertEqual(shapeChanges, 0, "Each unusable ratio and an explicitly square ratio share the same square geometry")
    }

    func testReplacementAndResetDetachVideoCallbacks() {
        let adView = PromoNativeAdView()
        let oldAd = FakeNativeAd(aspectRatio: 0, headline: "Old creative")
        let newAd = FakeNativeAd(aspectRatio: 9.0 / 16.0, headline: "New creative")
        var shapeChanges = 0
        adView.mediaAspectRatioDidChange = { shapeChanges += 1 }
        adView.configureContentViews(with: oldAd)
        adView.configureContentViews(with: newAd)

        XCTAssertNil(oldAd.videoController.delegate)
        XCTAssertTrue(newAd.videoController.delegate === adView)
        newAd.reportedAspectRatio = 16.0 / 9.0
        oldAd.videoController.simulatePlay()
        adView.videoControllerDidPlayVideo(oldAd.videoController)
        XCTAssertEqual(shapeChanges, 0, "An old controller must not announce a change in the replacement ad")

        newAd.videoController.simulatePlay()
        XCTAssertEqual(shapeChanges, 1)
        adView.reset()
        XCTAssertNil(newAd.videoController.delegate)
        newAd.reportedAspectRatio = 1
        newAd.videoController.simulatePlay()
        adView.videoControllerDidPlayVideo(newAd.videoController)
        XCTAssertEqual(shapeChanges, 1, "A callback already in flight must be harmless after reset")
    }

    func testSameAdReconfigurationKeepsVideoUpdatesConnected() {
        let adView = PromoNativeAdView()
        let nativeAd = FakeNativeAd(aspectRatio: 0, headline: "Creative")
        var shapeChanges = 0
        adView.mediaAspectRatioDidChange = { shapeChanges += 1 }
        adView.configureContentViews(with: nativeAd)
        adView.configureContentViews(with: nativeAd)

        XCTAssertEqual(shapeChanges, 0)
        XCTAssertTrue(nativeAd.videoController.delegate === adView)
        nativeAd.reportedAspectRatio = 16.0 / 9.0
        nativeAd.videoController.simulatePlay()
        XCTAssertEqual(shapeChanges, 1)
    }

    func testVideoShapeChangeNotifiesTheActiveHostWithoutReloading() throws {
        let provider = TestPromoProvider(result: .contentAvailable)
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let delegate = PromoViewDelegateSpy()
        promo.delegate = delegate
        promo.providers = [provider]
        wait(for: [delegate.updateExpectation], timeout: 1.0)

        let content = PromoNativeAdContentView(promoView: promo)
        let still = makePromoTestImage(size: CGSize(width: 90, height: 160), color: .blue)
        let nativeAd = FakeNativeAd(aspectRatio: 0,
                                    headline: "Creative",
                                    callToAction: "Install",
                                    images: [NativeAdImage(image: still)])
        content.nativeAd = nativeAd
        promo.contentView = content
        let adView = try XCTUnwrap(content.subviews.compactMap { $0 as? PromoNativeAdView }.first)
        let original = try geometry(of: adView)
        let updates = delegate.updateCount

        nativeAd.reportedAspectRatio = 16.0 / 9.0
        nativeAd.videoController.simulatePlay()
        let playing = try geometry(of: adView)

        XCTAssertEqual(delegate.updateCount, updates + 1)
        XCTAssertTrue(delegate.updatedProvider === provider)
        XCTAssertTrue(promo.contentView === content)
        XCTAssertTrue(content.nativeAd === nativeAd)
        XCTAssertEqual(provider.fetchCount, 1, "A shape change must resize the existing ad without fetching another")
        XCTAssertNotEqual(playing.fittingSize, original.fittingSize)
        XCTAssertEqual(playing.mediaFrame.width / playing.mediaFrame.height, 16.0 / 9.0, accuracy: 0.01)

        // A pooled or replaced content view must no longer resize the current card.
        promo.contentView = TestPromoContentView(promoView: promo)
        nativeAd.reportedAspectRatio = 9.0 / 16.0
        nativeAd.videoController.simulatePlay()
        XCTAssertEqual(delegate.updateCount, updates + 1)
        XCTAssertEqual(provider.fetchCount, 1)
    }

    private struct AdGeometry: Equatable {
        let fittingSize: CGSize
        let mediaFrame: CGRect
        let mediaContainerFrame: CGRect
        let headlineFrame: CGRect
        let actionFrame: CGRect
    }

    private func geometry(of adView: PromoNativeAdView) throws -> AdGeometry {
        let container = CGSize(width: 900, height: 600)
        let fittingSize = adView.sizeThatFits(container)
        adView.frame = CGRect(origin: .zero, size: container)
        adView.setNeedsLayout()
        adView.layoutIfNeeded()
        let mediaView = try XCTUnwrap(adView.mediaView)
        return AdGeometry(fittingSize: fittingSize,
                          mediaFrame: mediaView.frame,
                          mediaContainerFrame: try XCTUnwrap(mediaView.superview).frame,
                          headlineFrame: try XCTUnwrap(adView.headlineView).frame,
                          actionFrame: try XCTUnwrap(adView.callToActionView).frame)
    }

    func testAnUnknownShapeNoLongerClaimsTheWholeContainer() {
        // The bug this guards: measuring with a raw 0 sent the height through
        // `width / aspectRatio`, so the card took the full container and then
        // snapped down to the creative once its real shape arrived mid-swipe.
        // Squared off, it asks for a band it can actually fill.
        let container = CGSize(width: 700, height: 900)
        let squared = PromoNativeAdView.usableAspectRatio(reported: 0.0, stillSize: nil)
        let fitted = PromoNativeAdView.fittedMediaSize(containerSize: container, aspectRatio: squared)
        XCTAssertGreaterThan(fitted.height, 0)
        XCTAssertLessThan(fitted.height, container.height)
        XCTAssertEqual(fitted.width, fitted.height, accuracy: 1.0)
    }
}

extension PromoNativeAdContentViewTests {
    func testReuseRestoresCallToActionVisibilityInBothLayouts() throws {
        for aspect in [CGFloat(0.5), 1] {
            let adView = PromoNativeAdView()
            adView.maximumWidth = 1000
            adView.maximumHeight = 1000
            adView.configureContentViews(with: FakeNativeAd(aspectRatio: 0.5, headline: "No action"))
            adView.reset()
            adView.configureContentViews(with: FakeNativeAd(aspectRatio: aspect,
                                                           headline: "New creative",
                                                           callToAction: "Install"))

            let action = try XCTUnwrap(adView.callToActionView)
            XCTAssertTrue(action.superview === adView)
            XCTAssertFalse(action.isHidden, "A previous ad without a call to action must not hide the next ad's button")
        }
    }

    func testReuseReattachesBodyInSideBySideLayout() throws {
        let adView = PromoNativeAdView()
        adView.maximumWidth = 1000
        adView.maximumHeight = 1000
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 1, headline: "No body"))
        adView.reset()
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 0.5,
                                                       headline: "New creative",
                                                       body: "This body must be visible"))

        let body = try XCTUnwrap(adView.bodyView)
        XCTAssertFalse(body.isHidden)
        XCTAssertTrue(body.superview === adView, "A body removed by the prior stacked layout must be reattached")
        XCTAssertEqual((adView.headlineView as? UILabel)?.textAlignment, .center)
    }

    func testSideBySideSizingRespectsDefaultAndCustomContentCaps() throws {
        let adView = PromoNativeAdView()
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 9.0 / 16.0,
                                                       headline: "Portrait creative",
                                                       callToAction: "Install"))
        for limit in [CGSize(width: PromoNativeAdProvider.defaultMaximumContentWidth,
                             height: PromoNativeAdProvider.defaultMaximumContentHeight),
                      CGSize(width: 800, height: 400),
                      CGSize(width: 320, height: 400)] {
            adView.maximumWidth = limit.width
            adView.maximumHeight = limit.height
            let fitting = adView.sizeThatFits(CGSize(width: 1200, height: 1000))

            XCTAssertLessThanOrEqual(fitting.width, limit.width)
            XCTAssertLessThanOrEqual(fitting.height, limit.height)
            adView.frame = CGRect(origin: .zero, size: fitting)
            adView.setNeedsLayout()
            adView.layoutIfNeeded()
            let media = try XCTUnwrap(adView.mediaView)
            XCTAssertGreaterThan(media.frame.height, 0)
            XCTAssertEqual(media.frame.width / media.frame.height, 9.0 / 16.0, accuracy: 0.01)
            let alignment: NSTextAlignment = limit.width == 800 ? .center : .left
            XCTAssertEqual((adView.headlineView as? UILabel)?.textAlignment, alignment,
                           "The chosen layout must fit inside the capped width")
        }

        adView.maximumWidth = 1600
        adView.maximumHeight = 1100
        let expanded = adView.sizeThatFits(CGSize(width: 1400, height: 1000))
        XCTAssertGreaterThan(expanded.width, PromoNativeAdProvider.defaultMaximumContentWidth)
        XCTAssertGreaterThan(expanded.height, PromoNativeAdProvider.defaultMaximumContentHeight)
    }

    func testVideoResizeMeasuresTheFontsThatWillBeDisplayed() throws {
        let adView = PromoNativeAdView()
        adView.maximumWidth = 1000
        adView.maximumHeight = 1000
        let container = CGSize(width: 900, height: 600)
        let still = makePromoTestImage(size: CGSize(width: 90, height: 160), color: .blue)
        let nativeAd = FakeNativeAd(aspectRatio: 0,
                                    headline: "A title that can change size",
                                    body: "A body that can change size",
                                    callToAction: "Install",
                                    images: [NativeAdImage(image: still)])
        adView.configureContentViews(with: nativeAd)
        adView.frame = CGRect(origin: .zero, size: container)
        adView.setNeedsLayout()
        adView.layoutIfNeeded()
        let headline = try XCTUnwrap(adView.headlineView as? UILabel)
        let displayedFont = headline.font
        var hostMeasurement: CGSize?
        adView.mediaAspectRatioDidChange = { [weak adView] in
            hostMeasurement = adView?.sizeThatFits(container)
        }

        nativeAd.reportedAspectRatio = 16.0 / 9.0
        nativeAd.videoController.simulatePlay()
        let measurementBeforeLayout = try XCTUnwrap(hostMeasurement)
        XCTAssertEqual(headline.font, displayedFont, "Measurement must not change the currently displayed text")
        adView.layoutIfNeeded()
        let measurementAfterLayout = adView.sizeThatFits(container)

        XCTAssertEqual(measurementBeforeLayout, measurementAfterLayout,
                       "The video resize must measure the same font sizes that stacked layout displays")
    }

    func testPreferredSizeIsStableAcrossLayoutFormatChanges() throws {
        let adView = PromoNativeAdView()
        adView.maximumWidth = 1000
        adView.maximumHeight = 1000
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 0.5,
                                                       headline: "A title that wraps at narrower widths",
                                                       body: "Body text also changes its wrapping as the available width changes.",
                                                       callToAction: "Install"))
        for container in [CGSize(width: 900, height: 600),
                          CGSize(width: 360, height: 800),
                          CGSize(width: 900, height: 600)] {
            let measured = adView.sizeThatFits(container)
            adView.frame = CGRect(origin: .zero, size: measured)
            adView.setNeedsLayout()
            adView.layoutIfNeeded()

            XCTAssertEqual(adView.sizeThatFits(container), measured)
            let alignment: NSTextAlignment = container.width == 900 ? .center : .left
            XCTAssertEqual((adView.headlineView as? UILabel)?.textAlignment, alignment)
        }
    }

    func testHiddenOptionalViewsDoNotDisplaceMediaAfterReconfigurationOrReuse() throws {
        for resetFirst in [false, true] {
            let reused = PromoNativeAdView()
            reused.maximumWidth = 1000
            reused.maximumHeight = 1000
            let icon = makePromoTestImage(size: CGSize(width: 64, height: 64), color: .green)
            reused.configureContentViews(with: FakeNativeAd(aspectRatio: 0.5,
                                                            headline: "Old title",
                                                            body: "Old body",
                                                            callToAction: "Install",
                                                            icon: NativeAdImage(image: icon)))
            reused.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
            reused.setNeedsLayout()
            reused.layoutIfNeeded()
            if resetFirst { reused.reset() }

            let fresh = PromoNativeAdView()
            fresh.maximumWidth = 1000
            fresh.maximumHeight = 1000
            for adView in [reused, fresh] {
                adView.configureContentViews(with: FakeNativeAd(aspectRatio: 1,
                                                               headline: "New title",
                                                               callToAction: "Install"))
                adView.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                adView.setNeedsLayout()
                adView.layoutIfNeeded()
            }
            let reusedMedia = try XCTUnwrap(reused.mediaView)
            let freshMedia = try XCTUnwrap(fresh.mediaView)

            XCTAssertEqual(reusedMedia.frame, freshMedia.frame,
                           "Hidden icon/body frames from the prior ad must not shrink the new media")
            XCTAssertEqual(reusedMedia.superview?.frame, freshMedia.superview?.frame)
        }
    }
}

extension PromoNativeAdContentViewTests {
    func testCompactStackedMediaStartsBelowTheInlineCallToAction() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("Trait overrides require iOS 17")
        }
        let adView = PromoNativeAdView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 700, height: 300))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(adView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        adView.traitOverrides.verticalSizeClass = .compact
        window.layoutIfNeeded()
        XCTAssertEqual(adView.traitCollection.verticalSizeClass, .compact)
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 16.0 / 9.0,
                                                       headline: "Great App",
                                                       callToAction: "Install"))
        let preferred = adView.sizeThatFits(CGSize(width: 700, height: 300))
        adView.frame = CGRect(origin: .zero, size: preferred)
        adView.setNeedsLayout()
        adView.layoutIfNeeded()

        let action = try XCTUnwrap(adView.callToActionView)
        let media = try XCTUnwrap(adView.mediaView)
        let mediaContainer = try XCTUnwrap(media.superview)
        XCTAssertLessThanOrEqual(action.frame.maxY, mediaContainer.frame.minY,
                                "The media band must start below the inline call to action")
        XCTAssertFalse(action.frame.intersects(mediaContainer.frame),
                       "The media container is drawn above the action button and hides any overlap")
    }
}

extension PromoNativeAdContentViewTests {
    func testShortSideBySideCardFitsItsIconAndCopyAboveTheCallToAction() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("Trait overrides require iOS 17")
        }
        let adView = PromoNativeAdView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 700, height: 300))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(adView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        adView.traitOverrides.verticalSizeClass = .compact
        window.layoutIfNeeded()
        XCTAssertEqual(adView.traitCollection.verticalSizeClass, .compact)
        let icon = makePromoTestImage(size: CGSize(width: 64, height: 64), color: .green)
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 0.5,
                                                       headline: "Great App",
                                                       body: "Find new things to enjoy every day with everything you need in one convenient place.",
                                                       callToAction: "Install",
                                                       icon: NativeAdImage(image: icon)))
        let preferred = adView.sizeThatFits(CGSize(width: 500, height: 180))
        adView.frame = CGRect(origin: .zero, size: preferred)
        adView.setNeedsLayout()
        adView.layoutIfNeeded()

        let headline = try XCTUnwrap(adView.headlineView as? UILabel)
        let body = try XCTUnwrap(adView.bodyView)
        let action = try XCTUnwrap(adView.callToActionView)
        let iconView = try XCTUnwrap(adView.iconView)
        XCTAssertEqual(headline.textAlignment, .center, "Exercise the side-by-side layout")
        XCTAssertGreaterThan(iconView.frame.height, 0, "Keep the icon visible while fitting the column")
        XCTAssertLessThan(iconView.frame.height, 64, "The icon must shrink together with the copy")
        XCTAssertGreaterThan(body.frame.height, 0)
        XCTAssertLessThanOrEqual(iconView.frame.maxY, headline.frame.minY)
        XCTAssertLessThanOrEqual(body.frame.maxY, action.frame.minY,
                                "The combined icon and text block must fit above the call to action")
    }
}

extension PromoNativeAdContentViewTests {
    func testStackedNativeCopyAndBadgeFollowLayoutDirectionAcrossReuse() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let controller = UIViewController()
        window.rootViewController = controller
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 440))
        controller.view.addSubview(container)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let adView = PromoNativeAdView()
        container.addSubview(adView)
        let iconImage = makePromoTestImage(size: CGSize(width: 64, height: 64), color: .green)
        let ad = FakeNativeAd(aspectRatio: 16.0 / 9.0,
                              headline: "اكتشف تطبيقك الجديد",
                              body: "جرّب المزايا الجديدة كل يوم",
                              callToAction: "تثبيت",
                              icon: NativeAdImage(image: iconImage))
        adView.configureContentViews(with: ad)

        for (semantic, reuse) in [(UISemanticContentAttribute.forceLeftToRight, false),
                                  (.forceRightToLeft, false),
                                  (.forceLeftToRight, true),
                                  (.forceRightToLeft, true)] {
            container.semanticContentAttribute = semantic
            controller.traitOverrides.layoutDirection = semantic == .forceRightToLeft ? .rightToLeft : .leftToRight
            window.layoutIfNeeded()
            if reuse {
                adView.reset()
                adView.configureContentViews(with: ad)
            }
            adView.frame = container.bounds
            let preferred = adView.sizeThatFits(container.bounds.size)
            adView.setNeedsLayout()
            adView.layoutIfNeeded()

            let isRTL = semantic == .forceRightToLeft
            XCTAssertEqual(adView.effectiveUserInterfaceLayoutDirection, isRTL ? .rightToLeft : .leftToRight)
            let headline = try XCTUnwrap(adView.headlineView as? UILabel)
            let body = try XCTUnwrap(adView.bodyView as? UILabel)
            let icon = try XCTUnwrap(adView.iconView)
            let badge = try XCTUnwrap(adView.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Ad" })
            let paragraph = try XCTUnwrap(headline.attributedText?.attribute(.paragraphStyle,
                                                                            at: 0,
                                                                            effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertEqual(headline.textAlignment, isRTL ? .right : .left)
            XCTAssertEqual(body.textAlignment, isRTL ? .right : .left)
            XCTAssertEqual(paragraph.baseWritingDirection, isRTL ? .rightToLeft : .leftToRight)
            XCTAssertGreaterThan(paragraph.firstLineHeadIndent, badge.frame.width)
            if isRTL {
                XCTAssertGreaterThanOrEqual(icon.frame.minX, headline.frame.maxX)
                XCTAssertEqual(badge.frame.maxX, headline.frame.maxX, accuracy: 0.01)
                XCTAssertEqual(body.frame.maxX, headline.frame.maxX, accuracy: 0.01)
                XCTAssertLessThanOrEqual(icon.frame.maxX, adView.bounds.width - 20,
                                         "Keep the SDK's physical top-right AdChoices area clear")
            } else {
                XCTAssertLessThanOrEqual(icon.frame.maxX, headline.frame.minX)
                XCTAssertEqual(badge.frame.minX, headline.frame.minX, accuracy: 0.01)
                XCTAssertEqual(body.frame.minX, headline.frame.minX, accuracy: 0.01)
            }
            XCTAssertEqual(adView.sizeThatFits(container.bounds.size), preferred)
        }
    }

    func testSideBySideNativeLayoutMirrorsAssetsWithoutFlippingMediaOrSDKSubviews() throws {
        let adView = PromoNativeAdView()
        adView.maximumWidth = 1000
        adView.maximumHeight = 1000
        let adChoices = AdChoicesView(frame: CGRect(x: 780, y: 0, width: 20, height: 20))
        adView.addSubview(adChoices)
        adView.adChoicesView = adChoices
        let adChoicesFrame = adChoices.frame
        let iconImage = makePromoTestImage(size: CGSize(width: 64, height: 64), color: .green)
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 0.5,
                                                       headline: "اكتشف تطبيقك الجديد",
                                                       body: "جرّب المزايا الجديدة كل يوم",
                                                       callToAction: "تثبيت",
                                                       icon: NativeAdImage(image: iconImage)))
        var leftToRightFrames: [CGRect]?

        for semantic in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft, .forceLeftToRight] {
            adView.semanticContentAttribute = semantic
            adView.frame = CGRect(x: 0, y: 0, width: 800, height: 400)
            adView.setNeedsLayout()
            adView.layoutIfNeeded()

            let headline = try XCTUnwrap(adView.headlineView as? UILabel)
            let body = try XCTUnwrap(adView.bodyView)
            let icon = try XCTUnwrap(adView.iconView)
            let action = try XCTUnwrap(adView.callToActionView)
            let media = try XCTUnwrap(adView.mediaView)
            let mediaContainer = try XCTUnwrap(media.superview)
            let badge = try XCTUnwrap(adView.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Ad" })
            XCTAssertEqual(headline.textAlignment, .center)
            XCTAssertEqual(media.frame.width / media.frame.height, 0.5, accuracy: 0.01)
            XCTAssertEqual(adView.transform, .identity)
            XCTAssertEqual(media.transform, .identity, "Mirror asset positions, not the creative itself")
            XCTAssertEqual(adChoices.frame, adChoicesFrame, "AdChoices must stay at the physical top-right corner")
            XCTAssertTrue(adView.adChoicesView === adChoices)
            let frames = [headline, body, icon, action, badge, mediaContainer].map(\.frame)
            if semantic == .forceRightToLeft {
                XCTAssertLessThanOrEqual(mediaContainer.frame.maxX, headline.frame.minX)
                XCTAssertLessThanOrEqual(mediaContainer.frame.maxX, action.frame.minX)
                XCTAssertGreaterThan(badge.frame.midX, adView.bounds.midX)
                XCTAssertFalse(badge.frame.intersects(adChoicesFrame))
            } else {
                XCTAssertGreaterThanOrEqual(mediaContainer.frame.minX, headline.frame.maxX)
                XCTAssertLessThan(badge.frame.midX, adView.bounds.midX)
                if let originalFrames = leftToRightFrames {
                    XCTAssertEqual(frames, originalFrames, "Changing direction back must not accumulate mirroring")
                } else {
                    leftToRightFrames = frames
                }
            }
        }
    }

    func testCompactRTLNativeLayoutKeepsActionSeparateFromCopyAndMedia() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("Trait overrides require iOS 17")
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 700, height: 300))
        let controller = UIViewController()
        window.rootViewController = controller
        let adView = PromoNativeAdView()
        controller.view.addSubview(adView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        adView.semanticContentAttribute = .forceRightToLeft
        adView.traitOverrides.verticalSizeClass = .compact
        window.layoutIfNeeded()
        let iconImage = makePromoTestImage(size: CGSize(width: 64, height: 64), color: .green)
        adView.configureContentViews(with: FakeNativeAd(aspectRatio: 16.0 / 9.0,
                                                       headline: "اكتشف تطبيقك الجديد",
                                                       body: "جرّب المزايا الجديدة كل يوم",
                                                       callToAction: "تثبيت",
                                                       icon: NativeAdImage(image: iconImage)))
        let preferred = adView.sizeThatFits(window.bounds.size)
        adView.frame = CGRect(origin: .zero, size: preferred)
        adView.setNeedsLayout()
        adView.layoutIfNeeded()

        let headline = try XCTUnwrap(adView.headlineView)
        let body = try XCTUnwrap(adView.bodyView)
        let action = try XCTUnwrap(adView.callToActionView)
        let media = try XCTUnwrap(adView.mediaView)
        let mediaContainer = try XCTUnwrap(media.superview)
        XCTAssertEqual(adView.traitCollection.verticalSizeClass, .compact)
        XCTAssertLessThanOrEqual(action.frame.maxX, headline.frame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxX, body.frame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxY, mediaContainer.frame.minY)
        XCTAssertEqual(adView.sizeThatFits(window.bounds.size), preferred,
                       "RTL layout must retain the preferred size measured before layout")
    }
}
