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
                       CGSize(width: 320, height: 50))

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
