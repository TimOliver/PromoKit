//
//  PromoNativeAdProvider.swift
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

@objc(PMKPromoNativeAdProvider)
public class PromoNativeAdProvider: NSObject, PromoProvider {

    /// The Google ad identifier for this native ad
    private let adUnitID: String

    /// The loading object responsible for loading ads
    private var adLoader: GADAdLoader?

    /// The most recently loaded ad from the ad loader
    private var nativeAd: GADNativeAd?

    /// A background image generated by this provider
    private var mediaBackgroundImage: UIImage?

    // Store the result handler so we can call it when the ad has returned a value
    private var resultHandler: PromoProviderContentFetchHandler?

    // Store a reference to the promo view we can use when the ad delegate returns
    private weak var promoView: PromoView?

    /// Create new instance of a Google ad banner provider
    /// - Parameter adUnitID: The Google ad unit ID for this banner
    init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    // MARK: - PromoProvider Implementation

    public func didMoveToPromoView(_ promoView: PromoView) {
        // Capture a weak reference to our parent promo view since we'll be using
        // it to perform image generation and to force a reload if the Google ad changes
        self.promoView = promoView
    }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping PromoProviderContentFetchHandler) {
        // Save a reference to the result handler so we can call it when the Google ad delegate returns
        self.resultHandler = resultHandler

        // Kick off the ad request
        makeAdLoaderIfNeeded(with: promoView)
        adLoader?.load(GADRequest())
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
        adContentView.mediaBackgroundImage = mediaBackgroundImage
        return adContentView
    }

    public func shouldPlayInteractionAnimation(for promoView: PromoView, with touch: UITouch) -> Bool {
        // We only want to suppress the tap animation if the user taps the little Google ad info button in the top right corner
        guard let adView = promoView.contentView as? PromoNativeAdContentView else { return true }
        let adChoicesViewFrame = adView.adChoicesViewFrame
        if adChoicesViewFrame == .zero { return true }
        let location = touch.location(in: promoView.contentView)
        return !adChoicesViewFrame.insetBy(dx: -15.0, dy: -15.0).contains(location)
    }

    // MARK: - Private

    private func didReceiveResult(_ result: Result<Void, Error>) {
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
            // This was a subsequent reload, so just refresh the content view
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

        let viewAdOptions = GADNativeAdViewAdOptions()
        viewAdOptions.preferredAdChoicesPosition = .topRightCorner

        self.adLoader = GADAdLoader(adUnitID: adUnitID,
                                    rootViewController: promoView.rootViewController,
                                    adTypes: [.native],
                                    options: [videoOptions, mediaLoaderOptions, viewAdOptions])
        self.adLoader?.delegate = self
    }

    private func makeBlurredMediaImageIfAvailable(completion: @escaping () -> (Void)) {
        guard let image = nativeAd?.images?.first?.image else {
            completion()
            return
        }
        promoView?.backgroundQueue.addOperation {
            let fittingSize = CGSize(width: 500, height: 700)
            let blurredImage = PromoImageProcessing
                .blurredImage(image, radius: 50, brightness: -0.05, fittingSize: fittingSize)
            OperationQueue.main.addOperation { [weak self] in
                self?.mediaBackgroundImage = blurredImage
                completion()
            }
        }
    }
}

// MARK: - GADBannerViewDelegate

extension PromoNativeAdProvider: GADNativeAdLoaderDelegate {
    public func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        // Skip if the same ad was sent down
        if nativeAd == self.nativeAd {
            didReceiveResult(.success(()))
            return
        }

        self.nativeAd = nativeAd
        
        // Generate a blurred background image to position behind the media view
        makeBlurredMediaImageIfAvailable {
            self.didReceiveResult(.success(()))
        }
    }

    public func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        didReceiveResult(.failure(error))
    }
}
