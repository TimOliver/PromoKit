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

/// A reusable view displaying content loaded by a promo provider.
/// The hosting promo view pools content views by their concrete class.
@objc(PMKPromoContentView)
open class PromoContentView: UIView {

    /// The hosting promo view, which supplies properties such as corner radius and padding.
    private(set) public weak var promoView: PromoView?

    /// Creates a content view for the given host.
    /// - Parameter promoView: The promo view that owns this content view.
    public required init(promoView: PromoView) {
        self.promoView = promoView
        super.init(frame: .zero)
    }

    /// Called when the content view is removed and returned to the host's reuse pool.
    @objc open func prepareForReuse() {}

    /// Whether the displayed content view supplies its own size through `sizeThatFits`.
    /// Defaults to `false`. A zero size falls back to the provider's preferred size.
    @objc open var wantsSizingControl: Bool { false }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
