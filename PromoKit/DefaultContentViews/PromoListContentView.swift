//
//  PromoListContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A default content view that may be used with various types of providers.
/// It follows the typical 'list' style on iOS, similar to UITableView.
/// It consists of a title label, a detail label, and an optional image positioned
/// against the leading edge.
@objc(PMKPromoListContentView)
public class PromoListContentView: NSObject, PromoContentView {

    /// The reuse identifier associated with this particular instance
    public private(set) var reuseIdentifier: String

    /// Creates a new instance of a list content view.
    /// - Parameter reuseIdentifier: The reuse identifier used to fetch this instance from the promo view
    public required init(reuseIdentifier: String) {
        self.reuseIdentifier = reuseIdentifier
    }

    

}
