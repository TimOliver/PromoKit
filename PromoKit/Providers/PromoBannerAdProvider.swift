//
//  PromoBannerAdProvider.swift
//
//  Copyright 2024-2025 Timothy Oliver. All rights reserved.
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
#if PROMOKIT_GOOGLE_ADS
import PromoKit
#endif
import GoogleMobileAds

@objc(PMKPromoBannerAdSize)
public enum PromoBannerAdSize: Int {
    case standard // Standard iPhone size: 320x50
    case full     // Full iPad size: 468x60
}

/// A provider for Google ad banners that switches sizes as the available width changes.
@objc(PMKPromoBannerAdProvider)
public class PromoBannerAdProvider: NSObject, PromoProvider {

    /// Banner size preferences. Uses `.full` when included and the content width is
    /// at least 468 points; otherwise, falls back to the standard 320×50 banner.
    public var supportedBannerSizes: [PromoBannerAdSize] = [.standard, .full]

    /// Restricts banners to 320×50 points regardless of the hosting view's width.
    /// Exposed to Objective-C because `supportedBannerSizes` cannot be bridged directly.
    @objc public func restrictToStandardBannerSize() {
        supportedBannerSizes = [.standard]
    }

    /// The Google ad identifier for this banner
    private let adUnitID: String

    /// The Google banner view, created once and reused across fetches
    private let adView = BannerView()
    private var hostingPadding = UIEdgeInsets.zero
    private weak var promoView: PromoView?

    // Completed by the banner view's load delegate.
    private var resultHandler: PromoProviderContentFetchHandler?

    /// Creates a Google ad banner provider.
    /// - Parameter adUnitID: The Google ad unit ID for this banner
    @objc public init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    deinit {
        resultHandler = nil
    }

    public var isInternetAccessRequired: Bool { true }
    public var showsLoadingIndicatorDuringFetch: Bool { true }
    public var needsReloadOnSizeChange: Bool { true }

    /// Refetches only when the available content width selects a different banner size.
    /// Compares the underlying sizes because `AdSize` is not `Equatable`.
    public func shouldReloadForSizeChange(from oldSize: CGSize, to newSize: CGSize) -> Bool {
        let oldContentSize = CGRect(origin: .zero, size: oldSize).inset(by: hostingPadding).size
        let newContentSize = CGRect(origin: .zero, size: newSize).inset(by: hostingPadding).size
        return bannerSizeFor(promoSize: oldContentSize).size != bannerSizeFor(promoSize: newContentSize).size
    }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        self.promoView = promoView
        self.resultHandler = resultHandler
        // AdMob updates the creative before its success callback. Hide it until
        // contentView(for:) places it in the container that PromoView fades in.
        adView.isHidden = true
        adView.adUnitID = adUnitID
        adView.delegate = self
        adView.rootViewController = promoView.rootViewController
        hostingPadding = promoView.defaultContentPadding
        adView.adSize = bannerSizeFor(promoSize: promoView.bounds.inset(by: hostingPadding).size)
        adView.load(Request())
    }

    public func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        bannerSizeFor(promoSize: fittingSize).size
    }

    public func cornerRadius(for promoView: PromoView, with contentPadding: UIEdgeInsets) -> CGFloat {
        return contentPadding.left
    }

    public func contentView(for promoView: PromoView) -> PromoContentView {
        let containerView = promoView.dequeueContentView(for: PromoContainerContentView.self)
        containerView.addSubview(adView)
        // PromoView controls visibility through the container's fade-in.
        adView.isHidden = false
        return containerView
    }

    /// Clears the pending handler before invoking it, allowing reentrant fetches.
    private func didReceiveResult(_ result: Result<Void, Error>) {
        guard let handler = resultHandler else { return }
        resultHandler = nil
        switch result {
        case .success: handler(.contentAvailable)
        case .failure(let error):
            // A failed ordinary refresh keeps its existing card. Restore only
            // the banner still hosted by that card, before notifying the host.
            if let promoView, promoView.currentProvider === self,
               let contentView = promoView.contentView, adView.superview === contentView {
                adView.isHidden = false
            }
            // Preserve the underlying cause in logs before returning the generic failure.
            NSLog("[PromoKit] Banner ad failed to load (unit %@): %@",
                  adUnitID, error.localizedDescription)
            handler(.fetchRequestFailed)
        }
    }

    /// Selects a banner size using the available content width and size preferences.
    private func bannerSizeFor(promoSize: CGSize) -> AdSize {
        if supportedBannerSizes.contains(.full), promoSize.width >= 468 {
            return AdSizeFullBanner
        }
        return AdSizeBanner
    }
}

// MARK: - BannerViewDelegate

extension PromoBannerAdProvider: BannerViewDelegate {

    public func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        didReceiveResult(.success(()))
    }

    public func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        didReceiveResult(.failure(error))
    }
}
