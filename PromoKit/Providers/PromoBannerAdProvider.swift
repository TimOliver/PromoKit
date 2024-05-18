//
//  PromoAdMobBannerProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 24/4/2024.
//

import Foundation
import GoogleMobileAds

@objc(PMKPromoBannerAdSize)
public enum PromoBannerAdSize: Int {
    case standard // Standard iPhone size: 320x50
    case full     // Full iPad size: 468x60
}

@objc(PMKPromoBannerAdProvider)
public class PromoBannerAdProvider: NSObject, PromoProvider {

    /// The supported banner sizes that this promo can fit to
    public var supportedBannerSizes: [PromoBannerAdSize] = [.standard, .full]

    /// The Google ad identifier for this banner
    private let adUnitID: String

    /// The Google banner view
    private let adView = GADBannerView()

    // Store the result handler so we can call it when the ad has returned a value
    private var resultHandler: ((PromoProviderFetchContentResult) -> Void)?

    // Store a reference to the promo view we can use when the ad delegate returns
    private weak var promoView: PromoView?

    /// Create new instance of a Google ad banner provider
    /// - Parameter adUnitID: The Google ad unit ID for this banner
    init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    public var needsReloadOnSizeChange: Bool { true }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        adView.adUnitID = adUnitID
        adView.delegate = self
        adView.rootViewController = promoView.rootViewController
        adView.adSize = bannerSizeFor(promoSize: promoView.frame.size)
        adView.load(GADRequest())
        self.resultHandler = resultHandler

        // Show a loading spinner since the Google ad is blank while it's loading
        promoView.setIsLoading(true, animated: true)
        self.promoView = promoView
    }

    public func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        let defaultSize = CGSize(width: 320, height: 50)
        guard let superview = promoView.superview else {
            return defaultSize
        }
        if supportedBannerSizes.contains(.full) && superview.frame.width > 468 {
            return CGSize(width: 468, height: 60)
        }
        return defaultSize
    }

    public func cornerRadius(for promoView: PromoView, with contentPadding: UIEdgeInsets) -> CGFloat {
        return contentPadding.left
    }

    public func contentView(for promoView: PromoView) -> PromoContentView {
        let containerView = promoView.dequeueContentView(for: PromoContainerContentView.self)
        containerView.addSubview(adView)
        return containerView
    }

    private func didReceiveResult(_ result: Result<Void, Error>) {
        // Set the loading spinner to hide
        promoView?.setIsLoading(false, animated: true)
        promoView = nil

        // Inform the promo view of the results
        switch result {
        case .success(_):
            self.resultHandler?(.contentAvailable)
        case .failure(_):
            self.resultHandler?(.fetchRequestFailed)
        }
        self.resultHandler = nil
    }

    private func bannerSizeFor(promoSize: CGSize) -> GADAdSize {
        if supportedBannerSizes.contains(.full), promoSize.width > 468 {
            return GADAdSizeFullBanner
        }
        return GADAdSizeBanner
    }
}

// MARK: - GADBannerViewDelegate

extension PromoBannerAdProvider: GADBannerViewDelegate {

    public func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
        didReceiveResult(.success(()))
    }

    public func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
        didReceiveResult(.failure(error))
    }

}
