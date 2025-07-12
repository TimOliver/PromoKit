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

/// When querying for new content, these are the types of results that may be returned
@objc(PMKPromoProviderFetchContentResult)
public enum PromoProviderFetchContentResult: Int {
    case fetchRequestFailed    = 0 /// An error occurred (eg, no internet, or invalid connection) and another attempt should be made.
    case noContentAvailable    = 1 /// The fetch succeeded, but no valid content was found, so this provider should be skipped.
    case contentAvailable      = 2 /// The fetch succeeded and this provider has valid content it can show.
}

public typealias PromoProviderContentFetchHandler = ((PromoProviderFetchContentResult) -> Void)

/// A promo provider is a model object that manages fetching data for a promo item
/// and configuring a promo content view with that data.
@objc(PMKPromoProvider)
public protocol PromoProvider: AnyObject {

    /// The background color that the hosting promo view should be set to when this provider is visible.
    /// Default is `nil`, which defaults back to the background color state of the promo view.
    @objc optional var backgroundColor: UIColor? { get }

    /// Indicates that this provider requires an active internet connection (Default is false).
    /// If this is set to true, and the device doesn't have an internet connection, this provider
    /// will be deferred and then tried again once a valid connection is detected.
    @objc optional var isInternetAccessRequired: Bool { get }

    /// Providers with `isInternetAccessRequired` set to true, may also have the ability to save the results
    /// of their last fetch as local cache. In these cases, when this is `true`, even if there is no active
    /// internet connection, these providers will still be called in order to be given a chance to display their cache instead.
    @objc optional var isOfflineCacheAvailable: Bool { get }

    /// If true, when the frame size of the promo view changes, this provider will be given a chance to reload its content if it needs to.
    /// This is useful for banner ads who might need to load a larger or smaller variant to fit the new size.
    @objc optional var needsReloadOnSizeChange: Bool { get }

    /// For successful fetches, the amount of time that must pass before another fetch will be made.
    /// This is for providers who aren't real-time, so it isn't necessary to check them very often.
    @objc optional var fetchRefreshInterval: TimeInterval { get }

    /// Clears all of the local state and resets this provider back to where it was when it was first created.
    @objc optional func reset()

    /// Called when a provider has started being hosted by a promo view.
    /// This can be used by providers who need to retain a reference to the promo view for future updates.
    @objc optional func didMoveToPromoView(_ promoView: PromoView)

    /// The amount of padding between the content view and the edge of the promo view.
    /// If null, the promo view's `contentPadding` value will be used instead.
    @objc optional func contentPadding(for promoView: PromoView) -> UIEdgeInsets

    /// The provider's preferred corner radius given the promo view's current content padding.
    /// This can be used for providers whose view content require their edge content to be a specific value.
    /// Default value is the promo view's own corner radius
    @objc optional func cornerRadius(for promoView: PromoView, with contentPadding: UIEdgeInsets) -> CGFloat

    /// The preferred dimensions of the content view managed by this provider.
    /// If no content for the provider has been loaded yet, a 'best guess' should be provided.
    /// Once content has loaded, it's possible to access the provider's content view, which can be used to properly
    /// calculate the size.
    @objc optional func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize

    /// Perform an asynchronous fetch (ie make a web request) to see if this provider has any valid content to display
    /// When the fetch is complete, the result handler closure must be called.
    /// - Parameter resultHandler: The result handler that must be called once the fetch is complete.
    @objc func fetchNewContent(for promoView: PromoView, with resultHandler: @escaping PromoProviderContentFetchHandler)

    /// Requests the provider to fetch, and configure a content view with its current state.
    /// The promo view may be used to dequeue and recycle previously used content views.
    /// - Parameter promoView: The hosting promo view requesting the content view
    /// - Returns: A fully configured content view
    @objc func contentView(for promoView: PromoView) -> PromoContentView

    /// Indicates that when the user taps down on the promo view, a subtle interaction animation should play.
    /// Use this to disable the animation if the user taps a specific location in the content view.
    @objc optional func shouldPlayInteractionAnimation(for promoView: PromoView, with touch: UITouch) -> Bool
}
