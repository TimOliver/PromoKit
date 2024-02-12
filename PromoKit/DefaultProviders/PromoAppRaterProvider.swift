//
//  PromoAppRaterProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A promo provider that displays a call-to-action to rate this app on the App Store.
/// This can be a great default provider when all other providers are unavailable (such as when offline).
@objc(PMKPromoAppRaterProvider)
public class PromoAppRaterProvider: NSObject, PromoProvider {

    // Return the name of the provider object as a default
    public var identifier: String { "PromoAppRaterProvider" }

    // Return nil for the default background color
    public var backgroundColor: UIColor? { nil }

    // Return the default amount of insetting
    public func contentInsets(for promoView: UIView) -> UIEdgeInsets {
        promoView.layoutMargins
    }
}
