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
@objc(PMKPromoContentView)
public class PromoContentView: UIView {

    /// The parent promo view that owns this content view. This can be used to fetch state info
    /// about the promo view such as its current corner radius and insetting
    private(set) public weak var promoView: PromoView?

    /// Creates a new instance of this view with the provided re-use identifier
    required init(promoView: PromoView) {
        self.promoView = promoView
        super.init(frame: .zero)
    }
    
    /// Called after a content view instance has been reclaimed in 
    /// order to get it ready for its next use.
    @objc func prepareForReuse() {}

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

