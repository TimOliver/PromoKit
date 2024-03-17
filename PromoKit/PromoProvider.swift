//
//  PromoProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// When querying for new content, these are the types of results that may be returned
@objc(PMKPromoProviderFetchContentResult)
public enum PromoProviderFetchContentResult: Int {
    case noContentAvailable = 0 /// There is nothing for this provider to display, and should be skipped.
    case fetchRequestFailed = 1 /// An error occurred (eg, no internet) and another attempt should be made.
    case contentAvailable   = 2 /// The fetch succeeded and this provider has valid content it can show.
};

/// A promo provider is a model object that manages fetching data for a promo item
/// and configuring a promo content view with that data.
@objc(PMKPromoProvider)
public protocol PromoProvider: AnyObject {

    /// A unique string that can be used to identify and fetch this provider amongst others.
    @objc var identifier: String { get }

    /// The background color that the hosting promo view should be set to when this provider is visible.
    /// Default is `nil`, which defaults back to the background color state of the promo view.
    @objc optional var backgroundColor: UIColor? { get }

    /// Indicates that this provider requires an active internet connection (Default is false).
    /// If this is set to true, and the device doesn't have an internet connection, this provider
    /// will be deferred and then tried again once a valid connection is detected.
    @objc optional var isInternetAccessRequired: Bool { get }

    /// Perform an asynchronous fetch (ie make a web request) to see if this provider has any valid content to display
    /// When the fetch is complete, the result handler closure must be called.
    /// - Parameter resultHandler: The result handler that must be called once the fetch is complete.
    @objc func fetchNewContent(with resultHandler:((PromoProviderFetchContentResult) -> Void))
}
