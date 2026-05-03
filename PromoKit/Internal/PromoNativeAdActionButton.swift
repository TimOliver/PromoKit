//
//  PromoNativeAdActionButton.swift
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

/// A custom pill-shaped call-to-action button used in the native ad view.
/// On iOS 26 and later, the background renders as a tinted glass effect.
/// On earlier versions, it uses a solid tinted background.
final internal class PromoNativeAdActionButton: UIView {

    /// The text displayed in the button label
    var title: String? {
        get { label.text }
        set { label.text = newValue }
    }

    private let label = UILabel()
    private let solidBackground = UIView()
    private var glassView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true

        label.font = UIFont.boldSystemFont(ofSize: 18.0)
        label.textColor = .white
        label.textAlignment = .center

        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect()
            let glass = UIVisualEffectView(effect: effect)
            glass.clipsToBounds = true
            addSubview(glass)
            glass.contentView.addSubview(label)
            glassView = glass
        } else {
            if #available(iOS 13.0, *) {
                solidBackground.layer.cornerCurve = .continuous
            }
            addSubview(solidBackground)
            solidBackground.addSubview(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2.0
        layer.cornerRadius = radius
        if let glassView {
            glassView.frame = bounds
            glassView.layer.cornerRadius = radius
            label.frame = glassView.contentView.bounds
        } else {
            solidBackground.frame = bounds
            solidBackground.layer.cornerRadius = radius
            label.frame = bounds
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        if #available(iOS 26.0, *), let glassView,
           let effect = glassView.effect as? UIGlassEffect {
            effect.tintColor = tintColor
            glassView.effect = effect
        } else {
            solidBackground.backgroundColor = tintColor
        }
    }
}
