//
//  PromoTableListContentView.swift
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

/// A table-style content view with a title, optional detail text and footnote,
/// and an optional image on the left.
@objc(PMKPromoTableListContentView)
final public class PromoTableListContentView: PromoContentView {
    // MARK: - Public Properties

    /// A label that displays the title and subtitle text
    public let label = UILabel()

    /// A label that displays an optional footnote below the title and detail text.
    public let footnoteLabel = UILabel()

    /// An optional image displayed on the left side of the view.
    public let imageView = UIImageView()

    /// Spacing between the main text and footnote.
    private let labelSpacing = 6.0

    /// Creates a new instance of a list content view.
    /// - Parameter promoView: The promo view that owns this content view.
    public required init(promoView: PromoView) {
        super.init(promoView: promoView)

        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.numberOfLines = 0
        addSubview(label)

        footnoteLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        if #available(iOS 13.0, *) {
            footnoteLabel.textColor = .secondaryLabel
        } else {
            footnoteLabel.textColor = UIColor(white: 0.35, alpha: 1.0)
        }
        addSubview(footnoteLabel)

        imageView.clipsToBounds = true
        if #available(iOS 13.0, *) {
            imageView.layer.cornerCurve = .continuous
        }
        imageView.isHidden = true
        addSubview(imageView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Clears displayed text and images before reuse.
    public override func prepareForReuse() {
        label.text = nil
        footnoteLabel.text = nil
        footnoteLabel.frame = .zero
        footnoteLabel.isHidden = true
        imageView.image = nil
    }

    /// Configures the list content view with the provided text and image data
    /// - Parameters:
    ///   - title: The text that will be displayed as the main title.
    ///   - detailText: The text optionally shown below the main title.
    ///   - footnote: The text optionally shown below the title and detail text.
    ///   - image: The image optionally shown to the left of the text.
    public func configure(title: String, detailText: String? = nil, footnote: String? = nil, image: UIImage? = nil) {
        footnoteLabel.text = footnote

        let string = NSMutableAttributedString()

        // Title text
        let titleFont = UIFont.systemFont(ofSize: 17.0, weight: .bold)
        string.append(NSMutableAttributedString(string: title, attributes: [.font: titleFont]))

        // Detail text
        if let detailText {
            var detailColor = UIColor.black
            if #available(iOS 13.0, *) {
                detailColor = .label
            }
            let detailFont = UIFont.systemFont(ofSize: 15.0, weight: .regular)
            string.append(NSAttributedString(string: "\n"))
            string.append(NSAttributedString(string: detailText,
                                             attributes: [.font: detailFont, .foregroundColor: detailColor]))
        }

        label.attributedText = string

        imageView.image = image
        imageView.isHidden = (image == nil)

        setNeedsLayout()
    }
}

// MARK: - Layout
extension PromoTableListContentView {

    public override func layoutSubviews() {
        super.layoutSubviews()

        let size = bounds.size
        let imageSpacing = min(max(0, promoView?.contentPadding.left ?? 0), size.width)
        var xOffset = imageSpacing
        if !imageView.isHidden,
           let imageSize = imageView.image?.size,
           imageSize.width > 0, imageSize.height > 0 {
            // Keep the thumbnail within a row-height square and reserve at least
            // half of the available column width for the title and detail text.
            let maximumImageWidth = min(size.height, max(0, size.width - imageSpacing) * 0.5)
            let scale = min(maximumImageWidth / imageSize.width, size.height / imageSize.height)
            let imageFrameSize = CGSize(width: imageSize.width * scale,
                                        height: imageSize.height * scale)
            imageView.frame = CGRect(x: 0, y: (size.height - imageFrameSize.height) * 0.5,
                                     width: imageFrameSize.width, height: imageFrameSize.height)
            if let promoView = self.promoView {
                let radius = promoView.cornerRadius - promoView.contentPadding.top
                imageView.layer.cornerRadius = max(0, radius)
            }
            xOffset = imageView.frame.maxX + imageSpacing
        } else {
            imageView.frame = .zero
        }

        let textWidth = max(0, size.width - xOffset)
        let hasFootnote = !(footnoteLabel.text?.isEmpty ?? true)
        footnoteLabel.isHidden = !hasFootnote
        var footnoteHeight = 0.0
        var footnoteSpacing = 0.0
        if hasFootnote {
            let measuredSize = footnoteLabel.sizeThatFits(CGSize(width: textWidth, height: size.height))
            footnoteHeight = min(size.height, measuredSize.height)
            footnoteSpacing = min(labelSpacing, max(0, size.height - footnoteHeight))
        }

        let fittingSize = CGSize(width: textWidth,
                                 height: max(0, size.height - footnoteHeight - footnoteSpacing))
        let labelHeight = min(fittingSize.height, label.textRect(forBounds: CGRect(origin: .zero, size: fittingSize),
                                                               limitedToNumberOfLines: 4).height)
        let height = labelHeight + footnoteHeight + footnoteSpacing

        label.frame = CGRect(origin: CGPoint(x: xOffset, y: (size.height - height) * 0.5),
                             size: CGSize(width: fittingSize.width, height: labelHeight))
        footnoteLabel.frame = hasFootnote
            ? CGRect(x: xOffset, y: label.frame.maxY + footnoteSpacing, width: textWidth, height: footnoteHeight)
            : .zero
    }
}
