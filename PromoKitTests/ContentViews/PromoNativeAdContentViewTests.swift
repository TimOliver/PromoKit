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


extension PromoNativeAdContentViewTests {
    func testReuseClearsGoogleNativeAdRegistration() throws {
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 360, height: 420))
        let content = PromoNativeAdContentView(promoView: promo)
        content.nativeAd = FakeNativeAd(aspectRatio: 1.4, headline: "Old creative", callToAction: "Install")
        let inner = try XCTUnwrap(content.subviews.compactMap { $0 as? PromoNativeAdView }.first)
        XCTAssertNotNil(inner.nativeAd)
        content.prepareForReuse()
        XCTAssertNil(inner.nativeAd, "The SDK ad registration must be cleared when returning a view to the pool")
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
