//
//  PromoBlankContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 23/3/2024.
//

import UIKit

/// A default, blank content view that can be used for displaying empty content,
/// or simply for testing.
@objc(PMKPromoBlankContentView)
public class PromoBlankContentView: PromoContentView {
    
    required init(reuseIdentifier: String, promoView: PromoView) {
        super.init(reuseIdentifier: reuseIdentifier, promoView: promoView)
        backgroundColor = .red
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension PromoContentViewReuseIdentifier {
    static public let blank = "PMKPromoBlankContentView";
}
