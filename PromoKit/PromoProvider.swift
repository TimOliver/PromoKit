//
//  PromoProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A promo provider is a model object that manages fetching data for a promo item
/// and configuring a promo content view with that data.
@objc(PMKPromoProvider)
public protocol PromoProvider: AnyObject {

    /// A unique string that can be used to identify and fetch this provider amongst others. 
    @objc var identifier: String { get }

    /// The background color that the hosting promo view should be set to when this provider is visible.
    /// Default is `nil`, which defaults back to the background color state of the promo view.
    @objc var backgroundColor: UIColor? { get }

    /// The amount that the content view is inset by, from the boundary of the promo view.
    /// A different value can be provided depending on the current size class of the promo view.
    /// - Parameter promoView: The promo view hosting the content managed by this provider
    /// - Returns: The amount of insetting. Default values is `.zero`
    @objc func contentInsets(for promoView: UIView) -> UIEdgeInsets
}

// MARK: - Default Implementations

extension PromoProvider {

    // Return the name of the provider object as a default
    public var identifier: String {
        String(describing: type(of: self))
    }

    // Return nil for the default background color
    public var backgroundColor: UIColor? { nil }

    // Return nil for the default amount of insetting
    public func contentInsets(for promoView: UIView) -> UIEdgeInsets { .zero }
}
