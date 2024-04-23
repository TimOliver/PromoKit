//
//  PromoBlankContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 23/3/2024.
//

import UIKit

/// A default, blank content view that can be used for displaying empty content or simply for testing.
@objc(PMKPromoBlankContentView)
public class PromoBlankContentView: PromoContentView {
    
    required init(promoView: PromoView) {
        super.init(promoView: promoView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
