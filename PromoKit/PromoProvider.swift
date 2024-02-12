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
}

extension PromoProvider {

    // Return the name of the provider object as a default
    public var identifier: String {
        String(describing: type(of: self))
    }

    // Return nil for the default background color
    public var backgroundColor: UIColor? { nil }
}
