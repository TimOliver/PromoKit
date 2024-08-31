//
//  PromoBannerAdProvider.swift
//
//  Copyright 2024 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

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
    private var resultHandler: PromoProviderContentFetchHandler?

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

        // When calling `adView.load`, the ad automatically hides, so we need to manually show the loading spinner here
        promoView.setIsLoading(true, animated: true)
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
