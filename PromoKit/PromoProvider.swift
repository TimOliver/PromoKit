//
//  PromoProvider.swift
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

import UIKit

/// The result of a provider's content fetch.
@objc(PMKPromoProviderFetchContentResult)
public enum PromoProviderFetchContentResult: Int {
    /// The fetch failed and may be retried after the retry interval.
    case fetchRequestFailed = 0
    /// The fetch succeeded but found no content to display.
    case noContentAvailable = 1
    /// The fetch succeeded and found content to display.
    case contentAvailable = 2
}

public typealias PromoProviderContentFetchHandler = ((PromoProviderFetchContentResult) -> Void)

/// A promo provider is a model object that manages fetching data for a promo item
/// and configuring a promo content view with that data.
@objc(PMKPromoProvider)
public protocol PromoProvider: AnyObject {
    /// The background color to use while this provider is visible.
    /// Defaults to `nil`, preserving the host's background color.
    @objc optional var backgroundColor: UIColor? { get }

    /// Whether fetching requires internet access. Defaults to `false`.
    /// When `true`, offline fetches require `isOfflineCacheAvailable`.
    @objc optional var isInternetAccessRequired: Bool { get }

    /// Allows an internet-dependent provider to be fetched offline so it can display cached content.
    /// Defaults to `false`.
    @objc optional var isOfflineCacheAvailable: Bool { get }

    /// Whether the promo view shows a loading spinner during the fetch. Defaults to `false`.
    /// This does not remove the previously displayed content.
    @objc optional var showsLoadingIndicatorDuringFetch: Bool { get }

    /// Whether size changes can trigger a reload, such as loading a different banner size.
    /// Defaults to `false`.
    @objc optional var needsReloadOnSizeChange: Bool { get }

    /// When `needsReloadOnSizeChange` is `true`, decides whether a size transition needs a reload.
    /// Return `false` when both sizes can use the same content. If omitted, all size changes
    /// request a reload, subject to the provider's refresh or retry interval.
    @objc optional func shouldReloadForSizeChange(from oldSize: CGSize, to newSize: CGSize) -> Bool

    /// The minimum interval between fetches after `.contentAvailable` or `.noContentAvailable`.
    /// Defaults to zero. An explicit `PromoView.reload()` clears this interval's fetch history.
    @objc optional var fetchRefreshInterval: TimeInterval { get }

    /// Resets this provider's local state when called directly.
    /// `PromoView.reload()` resets coordinator state but does not call this method.
    @objc optional func reset()

    /// Called before each content fetch so the provider can record its hosting promo view.
    /// Store the view weakly if it is needed for later updates.
    @objc optional func didMoveToPromoView(_ promoView: PromoView)

    /// The amount of padding between the content view and the edge of the promo view.
    /// If omitted, the promo view's `defaultContentPadding` is used.
    @objc optional func contentPadding(for promoView: PromoView) -> UIEdgeInsets

    /// The provider's preferred corner radius given the promo view's current content padding.
    /// If omitted, the host's configured corner radius is used.
    @objc optional func cornerRadius(for promoView: PromoView, with contentPadding: UIEdgeInsets) -> CGFloat

    /// The preferred content dimensions, excluding the promo view's padding.
    /// Provide an estimate before content loads. A displayed content view with
    /// `wantsSizingControl` can supply its own size instead.
    @objc optional func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize

    /// Fetches content and reports whether it is available to display.
    /// - Parameters:
    ///   - promoView: The hosting promo view.
    ///   - resultHandler: Call once when the fetch completes. The coordinator accepts results from any queue.
    @objc func fetchNewContent(for promoView: PromoView, with resultHandler: @escaping PromoProviderContentFetchHandler)

    /// Creates or dequeues a content view and configures it with the provider's loaded content.
    /// - Parameter promoView: The hosting promo view requesting the content view
    /// - Returns: A fully configured content view
    @objc func contentView(for promoView: PromoView) -> PromoContentView

    /// Indicates that when the user taps down on the promo view, a subtle interaction animation should play.
    /// Use this to disable the animation if the user taps a specific location in the content view.
    /// - Parameters:
    ///   - promoView: The hosting promo view that received the touch
    ///   - touch: The UITouch object generated in this interaction
    /// - Returns: Whether to play the tap animation. Returning `false` does not suppress touch callbacks.
    @objc optional func shouldPlayInteractionAnimation(for promoView: PromoView, with touch: UITouch) -> Bool

    /// Called when a press begins on this provider while the promo view is not loading.
    /// Use this to capture touch state. The press may later end in activation or cancellation.
    /// - Parameters:
    ///   - promoView: The promo view that received the tap event
    ///   - touch: The touch that began the press.
    @objc optional func didTapDownInside(promoView: PromoView, with touch: UITouch)

    /// Called as a press moves, including outside the view's bounds, while this provider still owns it.
    /// Canceled presses do not receive further drag callbacks.
    /// - Parameters:
    ///   - promoView: The promo view that received the drag event
    ///   - touch: The touch whose location changed.
    @objc optional func didDragInside(promoView: PromoView, with touch: UITouch)

    /// Called when an uncanceled press ends inside the view while this provider's content is still active
    /// and the view is not loading. Replacing the provider or its content cancels the press.
    /// Use this callback for actions such as opening a URL or presenting an ad.
    /// - Parameters:
    ///   - promoView: The promo view that received the tap event
    ///   - touch: The touch that ended the press.
    @objc optional func didTapUpInside(promoView: PromoView, with touch: UITouch)

    /// Called on the provider that received touch-down when UIKit cancels the touch or the press ends
    /// without activation. Use this to clear touch state, including after content replacement.
    /// - Parameters:
    ///   - promoView: The promo view that received the tap event
    ///   - touch: The touch that ended or was canceled.
    @objc optional func didCancelTap(promoView: PromoView, with touch: UITouch)
}
