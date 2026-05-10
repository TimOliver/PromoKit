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
    }
}
