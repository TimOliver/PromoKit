//
//  PromoContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A content view is a reusable view that can be used to display a promotion
/// from data loaded by a provider object in the hosting promo view.
/// It uses the same recycling mechanism as UITableView to allow
/// different providers to use the same content view.
@objc(PMKContentView)
public protocol PromoContentView: AnyObject {

    /// A reuse identifier assigned to this instance of a content view so
    /// that it may get recycled by a hosting promo view for different providers.
    @objc var reuseIdentifier: String { get }

    /// Creates a new instance of a content view with the provided reuse identifier
    init(reuseIdentifier: String)

    /// Called after a content view instance has been reclaimed in order to get it ready for its next use.
    func prepareForReuse()
}

extension PromoContentView {
    func prepareForReuse() {}
}
