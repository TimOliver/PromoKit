//
//  PromoBlankContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 23/3/2024.
//

import UIKit

/// An empty container view that can be used to host specific view content owned by a provider.
@objc(PMKPromoContainerContentView)
final public class PromoContainerContentView: PromoContentView {
    
    required init(promoView: PromoView) {
        super.init(promoView: promoView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
