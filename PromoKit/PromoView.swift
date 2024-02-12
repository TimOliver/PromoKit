//
//  PromoView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 29/1/2024.
//

import UIKit

/// A promo view displays promotional or advertising content from a variety of sources,
/// determined and updated dynamically at runtime.
public class PromoView: UIView {

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .red
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

}
