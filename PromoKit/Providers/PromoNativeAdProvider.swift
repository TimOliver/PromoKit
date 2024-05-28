//
//  PromoNativeAdProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 24/4/2024.
//

import Foundation
import GoogleMobileAds

@objc(PMKPromoNativeAdProvider)
public class PromoNativeAdProvider: NSObject, PromoProvider {

    /// The Google ad identifier for this native ad
    private let adUnitID: String

    /// The loading object responsible for loading ads
    private var adLoader: GADAdLoader?

    /// The most recently loaded ad from the ad loader
    private var nativeAd: GADNativeAd?

    // Store the result handler so we can call it when the ad has returned a value
    private var resultHandler: ((PromoProviderFetchContentResult) -> Void)?

    // Store a reference to the promo view we can use when the ad delegate returns
    private weak var promoView: PromoView?

    /// Create new instance of a Google ad banner provider
    /// - Parameter adUnitID: The Google ad unit ID for this banner
    init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    public func didMoveToPromoView(_ promoView: PromoView) { self.promoView = promoView }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        makeAdLoaderIfNeeded(with: promoView)
        adLoader?.load(GADRequest())

        self.resultHandler = resultHandler

        // Show a loading spinner since the Google ad is blank while it's loading
        promoView.setIsLoading(true, animated: true)
        self.promoView = promoView
    }

    public func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        // Since this view can be so arbitrarily sized, use a square shape while we're loading.
        // We'll defer to the actual content view when loaded
        return CGSize(width: 85, height: 85)
    }

    public func cornerRadius(for promoView: PromoView, with contentPadding: UIEdgeInsets) -> CGFloat {
        return 30
    }

    public func contentPadding(for promoView: PromoView) -> UIEdgeInsets {
        UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
    }

    public func contentView(for promoView: PromoView) -> PromoContentView {
        let adContentView = promoView.dequeueContentView(for: PromoNativeAdContentView.self)
        adContentView.nativeAd = nativeAd
        return adContentView
    }

    private func didReceiveResult(_ result: Result<Void, Error>) {
        // Set the loading spinner to hide
        promoView?.setIsLoading(false, animated: true)

        // Inform the promo view of the results
        if resultHandler != nil {
            switch result {
            case .success(_):
                self.resultHandler?(.contentAvailable)
            case .failure(_):
                self.resultHandler?(.fetchRequestFailed)
            }
            self.resultHandler = nil
        } else {
            if case .success = result { promoView?.reloadContentView() }
        }
    }

    private func makeAdLoaderIfNeeded(with promoView: PromoView) {
        guard adLoader == nil else { return }

        let videoOptions = GADVideoOptions()
        videoOptions.startMuted = true
        videoOptions.clickToExpandRequested = true

        let mediaLoaderOptions = GADNativeAdMediaAdLoaderOptions()
        mediaLoaderOptions.mediaAspectRatio = .any

        self.adLoader = GADAdLoader(adUnitID: adUnitID,
                                    rootViewController: promoView.rootViewController,
                                    adTypes: [.native],
                                    options: [videoOptions, mediaLoaderOptions])
        self.adLoader?.delegate = self
    }
}

// MARK: - GADBannerViewDelegate

extension PromoNativeAdProvider: GADNativeAdLoaderDelegate {
    public func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        self.nativeAd = nativeAd
        didReceiveResult(.success(()))
    }

    public func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        didReceiveResult(.failure(error))
    }
}
