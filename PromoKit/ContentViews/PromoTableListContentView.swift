//
//  PromoTableListContentView.swift
//
//  Copyright 2024 Timothy Oliver. All rights reserved.
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

/// A default content view that can present promo content in a similar display style to UITableView cells.
/// It consists of a title label, a detail label positioned below it, and an optional image positioned
/// against the leading edge.
@objc(PMKPromoTableListContentView)
final public class PromoTableListContentView: PromoContentView {
    // MARK: - Public Properties

    /// A label that displays the title and subtitle text
    public let label = UILabel()

    /// A label that displays a headnote at the top
    public let headnoteLabel = UILabel()

    /// Stack view that aligns both views
    public let stackView = UIStackView()

    /// A label that displays the subtitle text
    public let subtitleLabel = UILabel()

    /// A label that displays the footnote text
    public let footnoteLabel = UILabel()

    // An optional image displayed horizontally along the leading edge of the view
    public let imageView = UIImageView()

    /// Spacing between headnote and text
    private let labelSpacing = 7.0

    /// Creates a new instance of a list content view.
    /// - Parameter reuseIdentifier: The reuse identifier used to fetch this instance from the promo view
    required init(promoView: PromoView) {
        super.init(promoView: promoView)

        stackView.axis = .vertical
        stackView.distribution = .fillProportionally
        addSubview(stackView)

        headnoteLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        if #available(iOS 13.0, *) {
            headnoteLabel.textColor = UIColor(dynamicProvider: { traits in
                traits.userInterfaceStyle == .dark ? .tertiaryLabel : .init(white: 0.45, alpha: 1.0)
            })
        } else {
            headnoteLabel.textColor = UIColor(white: 0.45, alpha: 1.0)
        }
        stackView.addArrangedSubview(headnoteLabel)

        label.adjustsFontSizeToFitWidth = true
        label.numberOfLines = 0
        stackView.addArrangedSubview(label)

        imageView.clipsToBounds = true
        if #available(iOS 13.0, *) {
            imageView.layer.cornerCurve = .continuous
        }
        imageView.isHidden = true
        addSubview(imageView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Reset all of the view state when the content view is being recycled
    public override func prepareForReuse() {
        // It is best practice to nil out all view content since these can contribute to
        // the overall memory footprint
        label.text = nil
        headnoteLabel.text = nil
        imageView.image = nil
    }

    /// Configures the list content view with the provided text and image data
    /// - Parameters:
    ///   - title: The text that will be displayed as the main title.
    ///   - detailText: The text optionally shown below the main title.
    ///   - image: The image optionally shown leading into the title.
    public func configure(title: String, detailText: String? = nil, headnote: String? = nil, image: UIImage? = nil) {
        // Headnote
        headnoteLabel.text = headnote

        let string = NSMutableAttributedString()

        // Title text
        let titleFont = UIFont.systemFont(ofSize: 17.0, weight: .bold)
        string.append(NSMutableAttributedString(string: title, attributes: [.font : titleFont]))

        // Detail text
        if let detailText {
            var detailColor = UIColor(white: 0.27, alpha: 1.0)
            if #available(iOS 13.0, *) {
                // Use a manual color here to make it darker on the background
                detailColor = UIColor(dynamicProvider: { traits in
                    traits.userInterfaceStyle == .dark ? .secondaryLabel : .init(white: 0.35, alpha: 1.0)
                })
            }
            let detailFont = UIFont.systemFont(ofSize: 15.0, weight: .regular)
            string.append(NSAttributedString(string: "\n"))
            string.append(NSAttributedString(string: detailText,
                                             attributes: [.font : detailFont, .foregroundColor: detailColor]))
        }

        label.attributedText = string

        imageView.image = image
        imageView.isHidden = (image == nil)

        setNeedsLayout()
    }
}

/// Layout
extension PromoTableListContentView {

    public override func layoutSubviews() {
        super.layoutSubviews()

        var xOffset = promoView?.contentPadding.left ?? 0.0
        if !imageView.isHidden {
            let imageSize = imageView.image?.size ?? .zero
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            imageView.frame.size = CGSize(width: imageSize.width * scale,
                                          height: imageSize.height * scale)
            if let promoView = self.promoView {
                let radius = promoView.cornerRadius - promoView.contentPadding.top
                imageView.layer.cornerRadius = max(0, radius)
            }
            xOffset = imageView.frame.maxX + (promoView?.contentPadding.left ?? 0.0)
        }

        var headnoteHeight = 0.0
        if headnoteLabel.text != nil {
            headnoteLabel.sizeToFit()
            headnoteHeight = headnoteLabel.frame.height + labelSpacing
        }

        let size = bounds.size
        let fittingSize = CGSize(width: size.width - xOffset, height: size.height - headnoteHeight)
        let labelHeight = label.textRect(forBounds: CGRect(origin: .zero, size: fittingSize), limitedToNumberOfLines: 4).height
        let height = min(size.height, labelHeight + headnoteHeight)

        stackView.frame = CGRect(origin: CGPoint(x: xOffset, y: (size.height - height) * 0.5),
                                 size: CGSize(width: fittingSize.width, height: height))
    }
}
