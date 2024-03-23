//
//  PromoProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A class that providers can extend in order to globally expose their default identifier strings.
@objc(PMKPromoProviderIdentifier)
public class PromoProviderIdentifier: NSObject { }

/// When querying for new content, these are the types of results that may be returned
@objc(PMKPromoProviderFetchContentResult)
public enum PromoProviderFetchContentResult: Int {
    case fetchRequestFailed = 0 /// An error occurred (eg, no internet) and another attempt should be made.
    case noContentAvailable = 1 /// The fetch succeeded, but no valid content was found, so this provider should be skipped.
    case contentAvailable   = 2 /// The fetch succeeded and this provider has valid content it can show.
};

/// A promo provider is a model object that manages fetching data for a promo item
/// and configuring a promo content view with that data.
@objc(PMKPromoProvider)
public protocol PromoProvider: AnyObject {

    /// An identifier that can be used to uniquely find this provider in a list of providers.
    /// This can be a default value statically supplied by the provider, or specific providers
    /// can choose to override this if it is expected a list of providers might have multiple copies.
    @objc var identifier: String { get }

    /// The background color that the hosting promo view should be set to when this provider is visible.
    /// Default is `nil`, which defaults back to the background color state of the promo view.
    @objc optional var backgroundColor: UIColor? { get }

    /// Indicates that this provider requires an active internet connection (Default is false).
    /// If this is set to true, and the device doesn't have an internet connection, this provider
    /// will be deferred and then tried again once a valid connection is detected.
    @objc optional var isInternetAccessRequired: Bool { get }

    /// For successful fetches, the amount of time that must pass before another fetch will be made.
    /// This is for providers who aren't real-time, so it is necessary to check them very often.
    @objc optional var fetchRefreshInterval: TimeInterval { get }

    /// Clears all of the local state and resets this provider back to where it was when 
    /// it was first created.
    @objc optional func reset()

    /// Perform an asynchronous fetch (ie make a web request) to see if this provider has any valid content to display
    /// When the fetch is complete, the result handler closure must be called.
    /// - Parameter resultHandler: The result handler that must be called once the fetch is complete.
    @objc func fetchNewContent(with resultHandler:@escaping ((PromoProviderFetchContentResult) -> Void))

    /// Requests the provider to fetch, and configure a content view with its current state.
    /// The promo view maye be used to dequeue and recycle previously used content views.
    /// - Parameter promoView: The hosting promo view requesting the content view
    /// - Returns: A fully configured content view
    @objc func contentView(for promoView: PromoView) -> PromoContentView
}
