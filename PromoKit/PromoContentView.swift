//
//  PromoContentView.swift
//
//  Copyright 2024-2025 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

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

    /// By default, the provider will always determine appropriate sizing.
    /// However for complex content views whose size depends on the loaded content,
    /// return `true` in order to enable `sizeThatFits` for the promo view size.
    @objc public var wantsSizingControl: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
