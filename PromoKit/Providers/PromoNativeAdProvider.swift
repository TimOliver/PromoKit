//
//  PromoNativeAdProvider.swift
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

/// A provider for loading and displaying a full-size native Google AdMob ad.
/// The ad is rendered using native UIKit components and can fluidly resize itself
/// to fit any available outer view size.
@objc(PMKPromoNativeAdProvider)
public class PromoNativeAdProvider: NSObject, PromoProvider {

    private struct Constants {
        // Maximum press duration before cancelling the interaction animation.
        static let adTapTimeout = 1.5
        // The distance the finger can be dragged before the ad tap is cancelled
        static let adTapDistanceThreshold: CGFloat = 44
    }

    /// The default ceiling on a native ad card's width.
    @objc public static let defaultMaximumContentWidth: CGFloat = 500

    /// The default ceiling on a native ad card's height.
    @objc public static let defaultMaximumContentHeight: CGFloat = 750

    /// Maximum preferred card width. Raise this before measuring if a wider card
    /// is needed; stretching a measured card can distort its media layout.
    @objc public var maximumContentWidth: CGFloat = PromoNativeAdProvider.defaultMaximumContentWidth

    /// Maximum preferred card height.
    @objc public var maximumContentHeight: CGFloat = PromoNativeAdProvider.defaultMaximumContentHeight

    /// The Google ad identifier for this native ad
    private let adUnitID: String

    /// The loading object responsible for loading ads. Re-created on each fetch to discard stale callbacks.
    private var adLoader: AdLoader?
    private var fetchToken = UUID()

    /// The most recently loaded native ad returned by the ad loader
    private var nativeAd: NativeAd?

    /// A blurred, darkened version of the ad's first image, used as the media background
    private var mediaBackgroundImage: UIImage?

    // The result handler captured at the start of a fetch and called once the ad loads or fails
    private var resultHandler: PromoProviderContentFetchHandler?

    // Hosting view used for background work and content updates.
    private weak var promoView: PromoView?

    // The point where the user first touched down, used to detect drags that should cancel the tap
    private var firstTapLocation: CGPoint?

    // Cancels the interaction animation after a long press.
    private var tapDownTimer: Timer?

    /// Creates a Google native ad provider.
    /// - Parameter adUnitID: The Google ad unit ID for this native ad.
    @objc public init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    deinit {
        // The run loop retains the timer until it fires or is invalidated.
        tapDownTimer?.invalidate()
        resultHandler = nil
    }

    // MARK: - PromoProvider Implementation

    public var isInternetAccessRequired: Bool { true }

    public func didMoveToPromoView(_ promoView: PromoView) {
        self.promoView = promoView
    }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping PromoProviderContentFetchHandler) {
        self.resultHandler = resultHandler
        fetchToken = UUID()

        // Discard any in-flight loader so its callbacks can't reach us
        adLoader?.delegate = nil
        adLoader = nil

        makeAdLoaderIfNeeded(with: promoView)
        adLoader?.load(Request())
    }

    public func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        // Use a loading placeholder until the content view can measure the ad.
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
        // Set sizing limits before assigning the ad, which triggers measurement and layout.
        adContentView.maximumContentWidth = maximumContentWidth
        adContentView.maximumContentHeight = maximumContentHeight
        adContentView.nativeAd = nativeAd
        adContentView.mediaBackgroundImage = mediaBackgroundImage
        return adContentView
    }

    public func shouldPlayInteractionAnimation(for promoView: PromoView, with touch: UITouch) -> Bool {
        guard let adContentView = promoView.contentView as? PromoNativeAdContentView else { return false }

        // Cancel the animation if the user taps in the outer margin between the ad view and the background view.
        guard adContentView.frame.contains(touch.location(in: promoView)) else { return false }

        // Don't play the tap animation if the user was aiming for the ad choices view.
        let adChoicesViewFrame = adContentView.adChoicesViewFrame
        guard adChoicesViewFrame != .zero else { return true }

        // Give AdChoices a minimum 44×44-point hit target.
        let adChoicesViewPaddedFrame = adChoicesViewFrame
            .insetBy(
                dx: -max(0, 44.0 - adChoicesViewFrame.width) * 0.5,
                dy: -max(0, 44.0 - adChoicesViewFrame.height) * 0.5
            )
        return !adChoicesViewPaddedFrame.contains(touch.location(in: adContentView))
    }

    public func didTapDownInside(promoView: PromoView, with touch: UITouch) {
        // Match native ad tap cancellation by ending our animation after a long
        // press or a drag beyond adTapDistanceThreshold.
        let touchPoint = touch.location(in: promoView)
        guard let contentView = promoView.contentView, contentView.frame.contains(touchPoint) else { return }
        firstTapLocation = touch.location(in: contentView)
        guard tapDownTimer == nil else { return }
        tapDownTimer = Timer.scheduledTimer(withTimeInterval: Constants.adTapTimeout, repeats: false, block: { [weak self] _ in
            guard let self else { return }
            self.promoView?.cancelTapInteraction(animated: true)
            self.resetAdTimeout()
        })
    }

    public func didDragInside(promoView: PromoView, with touch: UITouch) {
        guard let firstTapLocation, let contentView = promoView.contentView else { return }
        let newPoint = touch.location(in: contentView)
        guard abs(newPoint.x - firstTapLocation.x) > Constants.adTapDistanceThreshold
                || abs(newPoint.y - firstTapLocation.y) > Constants.adTapDistanceThreshold else { return }
        promoView.cancelTapInteraction(animated: true)
        resetAdTimeout()
    }

    public func didTapUpInside(promoView: PromoView, with touch: UITouch) {
        self.resetAdTimeout()
    }

    public func didCancelTap(promoView: PromoView, with touch: UITouch) {
        self.resetAdTimeout()
    }

    private func resetAdTimeout() {
        tapDownTimer?.invalidate()
        tapDownTimer = nil
        firstTapLocation = nil
    }

    // MARK: - Private

    /// Clears the pending handler before invoking it, allowing reentrant fetches.
    /// A success without a pending handler refreshes this provider's displayed content.
    private func didReceiveResult(_ result: Result<Void, Error>) {
        if let handler = resultHandler {
            resultHandler = nil
            switch result {
            case .success:
                handler(.contentAvailable)
            case .failure(let error):
                // Preserve the underlying cause before returning the generic failure.
                NSLog("[PromoKit] Native ad failed to load (unit %@): %@",
                      adUnitID, error.localizedDescription)
                handler(.fetchRequestFailed)
            }
        } else {
            if case .success = result, promoView?.currentProvider === self {
                promoView?.reloadContentView()
            }
        }
    }

    /// Creates an `AdLoader` configured for native ads if one does not already exist.
    private func makeAdLoaderIfNeeded(with promoView: PromoView) {
        guard adLoader == nil else { return }

        let videoOptions = VideoOptions()
        videoOptions.shouldStartMuted = true
        videoOptions.isClickToExpandRequested = true

        let mediaLoaderOptions = NativeAdMediaAdLoaderOptions()
        mediaLoaderOptions.mediaAspectRatio = .any

        let viewAdOptions = NativeAdViewAdOptions()
        viewAdOptions.preferredAdChoicesPosition = .topRightCorner

        self.adLoader = AdLoader(adUnitID: adUnitID,
                                 rootViewController: promoView.rootViewController,
                                 adTypes: [.native],
                                 options: [videoOptions, mediaLoaderOptions, viewAdOptions])
        self.adLoader?.delegate = self
    }

    /// Blurs the first ad image off the main thread, completing on the main queue
    /// only if the request is still current. Completes immediately when no image exists.
    private func makeBlurredMediaImageIfAvailable(for nativeAd: NativeAd, token: UUID,
                                                  completion: @escaping () -> Void) {
        guard let image = nativeAd.images?.first?.image else {
            mediaBackgroundImage = nil
            completion()
            return
        }
        promoView?.backgroundQueue.addOperation { [weak self] in
            let fittingSize = CGSize(width: 500, height: 700)
            let blurredImage = PromoImageProcessing
                .blurredImage(image, radius: 50, brightness: -0.05, fittingSize: fittingSize)
            OperationQueue.main.addOperation { [weak self] in
                guard let self, self.fetchToken == token, self.nativeAd === nativeAd else { return }
                self.mediaBackgroundImage = blurredImage
                completion()
            }
        }
    }
}

// MARK: - NativeAdLoaderDelegate

extension PromoNativeAdProvider: NativeAdLoaderDelegate {
    public func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        guard adLoader === self.adLoader else { return }
        // Reuse the existing backdrop when the SDK returns the same ad.
        if nativeAd == self.nativeAd {
            didReceiveResult(.success(()))
            return
        }

        self.nativeAd = nativeAd

        let token = fetchToken
        makeBlurredMediaImageIfAvailable(for: nativeAd, token: token) { [weak self] in
            guard let self, self.fetchToken == token, self.nativeAd === nativeAd else { return }
            self.didReceiveResult(.success(()))
        }
    }

    public func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        guard adLoader === self.adLoader else { return }
        didReceiveResult(.failure(error))
    }
}
