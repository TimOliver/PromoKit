//
//  PromoContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A class that content view can extend in order to globally expose their default reuse identifiers
/// that can be used by multiple providers to share the same content view.
@objc(PMKPromoContentViewReuseIdentifier)
public class PromoContentViewReuseIdentifier: NSObject { }

/// A content view is a reusable view that can be used to display a promotion
/// from data loaded by a provider object in the hosting promo view.
/// It uses the same recycling mechanism as UITableView to allow
/// different providers to use the same content view.
@objc(PMKContentView)
public protocol PromoContentView: AnyObject {
    /// Called after a content view instance has been reclaimed in order to get it ready for its next use.
    @objc optional func prepareForReuse()
}

