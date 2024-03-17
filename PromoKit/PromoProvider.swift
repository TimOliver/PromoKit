//
//  PromoProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// When querying for new content, these are the types of results that may be returned
@objc(PMKPromoProviderFetchContentResult)
enum PromoProviderFetchContentResult: Int {
    case offlineAvailable    = 0 /// An offline version is available, whether default content, or valid cache from a previous request.
    case noNewContent        = 1 /// The query succeeded, but there was no new content to show.
    case newContentAvailable = 2 /// The query succeeded, and there is new content to show.
    case fetchRequestFailed  = 3 /// An error occurred (eg, no internet) and another attempt should be made.
};

/// A promo provider is a model object that manages fetching data for a promo item
/// and configuring a promo content view with that data.
@objc(PMKPromoProvider)
public protocol PromoProvider: AnyObject {

    /// A unique string that can be used to identify and fetch this provider amongst others. 
    @objc var identifier: String { get }

    /// The background color that the hosting promo view should be set to when this provider is visible.
    /// Default is `nil`, which defaults back to the background color state of the promo view.
    @objc var backgroundColor: UIColor? { get }

    /// Indicates that this provider requires an active internet connection (Default is false).
    /// If this is set to true, and the device doesn't have an internet connection, this provider
    /// will be deferred and then tried again once a valid connection is detected.
    @objc var isInternetAccessRequired: Bool { get }

    /// The type of content view that will be used to present the data managed by this provider.
    @objc var contentViewClass: AnyClass { get }

    /// The amount that the content view is inset by, from the boundary of the promo view.
    /// A different value can be provided depending on the current size class of the promo view.
    /// - Parameter promoView: The promo view hosting the content managed by this provider
    /// - Returns: The amount of insetting. Default values is `.zero`
    @objc func contentInsets(for promoView: UIView) -> UIEdgeInsets
}

// MARK: - Default Protocol Implementations

extension PromoProvider {
    public var identifier: String { String(describing: type(of: self)) }
    public var backgroundColor: UIColor? { nil }
    public var isInternetAccessRequired: Bool { false }
    public var contentViewClass: AnyClass { UIView.self }
    public func contentInsets(for promoView: UIView) -> UIEdgeInsets { .zero }
}
