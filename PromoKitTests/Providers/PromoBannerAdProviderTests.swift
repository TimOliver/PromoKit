import XCTest
import UIKit
import GoogleMobileAds
@testable import PromoKit
@testable import PromoKitGoogleAds

@MainActor
final class PromoBannerAdProviderTests: XCTestCase {

    func testBannerProviderConfigurationAndReloadBuckets() {
        let provider = PromoBannerAdProvider(adUnitID: "test-banner")

        XCTAssertTrue(provider.isInternetAccessRequired)
        XCTAssertTrue(provider.showsLoadingIndicatorDuringFetch)
        XCTAssertTrue(provider.needsReloadOnSizeChange)
        XCTAssertFalse(provider.shouldReloadForSizeChange(from: CGSize(width: 320, height: 50),
                                                          to: CGSize(width: 467, height: 60)))
        XCTAssertTrue(provider.shouldReloadForSizeChange(from: CGSize(width: 467, height: 60),
                                                         to: CGSize(width: 468, height: 60)))

        provider.restrictToStandardBannerSize()

        XCTAssertEqual(provider.supportedBannerSizes, [.standard])
        XCTAssertFalse(provider.shouldReloadForSizeChange(from: CGSize(width: 320, height: 50),
                                                          to: CGSize(width: 600, height: 60)))
    }

    func testBannerPreferredContentSizeUsesSuperviewWidthAndRestriction() {
        let provider = PromoBannerAdProvider(adUnitID: "test-banner")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))

        XCTAssertEqual(provider.preferredContentSize(fittingSize: CGSize(width: 600, height: 200),
                                                     for: promoView),
                       CGSize(width: 468, height: 60))

        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 200))
        hostView.addSubview(promoView)

        XCTAssertEqual(provider.preferredContentSize(fittingSize: CGSize(width: 600, height: 200),
                                                     for: promoView),
                       CGSize(width: 468, height: 60))

        provider.restrictToStandardBannerSize()

        XCTAssertEqual(provider.preferredContentSize(fittingSize: CGSize(width: 600, height: 200),
                                                     for: promoView),
                       CGSize(width: 320, height: 50))
        XCTAssertEqual(provider.cornerRadius(for: promoView,
                                             with: UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)),
                       7)
    }

    func testBannerContentViewHostsAndUnhidesBannerView() {
        let provider = PromoBannerAdProvider(adUnitID: "test-banner")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))

        let contentView = provider.contentView(for: promoView)
        guard let containerView = contentView as? PromoContainerContentView else {
            return XCTFail("Banner ads should be hosted in a container content view")
        }

        XCTAssertEqual(containerView.subviews.count, 1)
        XCTAssertFalse(containerView.subviews[0].isHidden)
    }

    func testBannerDelegateCallbacksResolveFetchResults() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))

        let successProvider = PromoBannerAdProvider(adUnitID: "test-banner")
        let success = expectation(description: "Banner success resolves content")
        successProvider.fetchNewContent(for: promoView) { result in
            XCTAssertEqual(result, .contentAvailable)
            success.fulfill()
        }
        successProvider.bannerViewDidReceiveAd(BannerView())
        wait(for: [success], timeout: 1.0)

        let failureProvider = PromoBannerAdProvider(adUnitID: "test-banner")
        let failure = expectation(description: "Banner failure resolves fetch failure")
        failureProvider.fetchNewContent(for: promoView) { result in
            XCTAssertEqual(result, .fetchRequestFailed)
            failure.fulfill()
        }
        failureProvider.bannerView(BannerView(),
                                   didFailToReceiveAdWithError: NSError(domain: "PromoKitTests", code: 1))
        wait(for: [failure], timeout: 1.0)
    }
}


extension PromoBannerAdProviderTests {
    func testBannerSizingRespectsFittingWidth() {
        let provider = PromoBannerAdProvider(adUnitID: "audit-banner")
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))
        parent.addSubview(view)
        let preferred = provider.preferredContentSize(fittingSize: CGSize(width: 320, height: 100), for: view)
        XCTAssertEqual(preferred, CGSize(width: 320, height: 50), "A narrow column in a wide superview must get a fitting banner")
    }
}

// A banner's requested size must not follow the window. PromoKit refetches when a
// resize crosses a banner-size boundary, so a provider free to widen on a roomy
// window would issue a fresh ad request every time a split-screen divider crossed
// that boundary — a stream of requests for one placement.
@MainActor
final class PromoBannerAdProviderFixedSizeTests: XCTestCase {

    func testUnrestrictedProviderRefetchesAcrossTheSizeBoundary() {
        // The default behaviour, and the reason the restriction exists.
        let provider = PromoBannerAdProvider(adUnitID: "test-banner")
        XCTAssertTrue(provider.shouldReloadForSizeChange(from: CGSize(width: 360, height: 50),
                                                         to: CGSize(width: 800, height: 60)))
    }

    func testRestrictedProviderNeverReportsASizeChange() {
        let provider = PromoBannerAdProvider(adUnitID: "test-banner")
        provider.restrictToStandardBannerSize()
        for (from, to) in [(320.0, 1194.0), (1194.0, 320.0), (480.0, 500.0)] {
            XCTAssertFalse(provider.shouldReloadForSizeChange(from: CGSize(width: from, height: 60),
                                                              to: CGSize(width: to, height: 60)),
                           "a standard-only banner must not refetch going \(from) -> \(to)")
        }
    }
}
