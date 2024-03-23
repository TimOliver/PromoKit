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
public class PromoBlankContentView: UIView, PromoContentView {
    private(set) public var reuseIdentifier: String

    convenience init() {
        self.init(reuseIdentifier: PromoContentViewReuseIdentifier.blank)
    }

    public required init(reuseIdentifier: String) {
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: CGRectZero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension PromoContentViewReuseIdentifier {
    static public let blank = "PMKPromoBlankContentView";
}
