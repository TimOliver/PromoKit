//
//  PromoListContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A default content view that can present promo content in a similar display style to UITableView cells.
/// It consists of a title label, a detail label positioned below it, and an optional image positioned
/// against the leading edge.
@objc(PMKPromoTableListContentView)
public class PromoTableListContentView: PromoContentView {

    // MARK: - Public Properties

    /// A label that displays both the title and subtitle text
    public let label = UILabel()

    // An optional image displayed horizontally along the leading edge of the view
    public let imageView = UIImageView()

    /// Creates a new instance of a list content view.
    /// - Parameter reuseIdentifier: The reuse identifier used to fetch this instance from the promo view
    required init(promoView: PromoView) {
        super.init(promoView: promoView)

        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        label.numberOfLines = 0
        addSubview(label)

        imageView.clipsToBounds = true
        if #available(iOS 13.0, *) {
            imageView.layer.cornerCurve = .continuous
        }
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
        imageView.image = nil
    }

    /// Configures the list content view with the provided text and image data
    /// - Parameters:
    ///   - title: The text that will be displayed as the main title.
    ///   - detailText: The text optionally shown below the main title.
    ///   - image: The image optionally shown leading into the title.
    public func configure(title: String, detailText: String? = nil, image: UIImage? = nil) {
        let titleFont = UIFont.systemFont(ofSize: 28, weight: .bold)
        let string = NSMutableAttributedString(string: title, attributes: [.font : titleFont]);
        if let detailText {
            var detailColor = UIColor(white: 0.27, alpha: 1.0)
            if #available(iOS 13.0, *) {
                // Use a manual color here to make it darker on the background
                detailColor = UIColor(dynamicProvider: { traits in
                    traits.userInterfaceStyle == .dark ? .systemGray : .init(white: 0.35, alpha: 1.0)
                })
            }

            let detailFont = UIFont.systemFont(ofSize: 23.0, weight: .semibold)
            string.append(NSAttributedString(string: "\n"))
            string.append(NSAttributedString(string: detailText,
                                             attributes: [.font : detailFont, .foregroundColor: detailColor]))
        }
        label.attributedText = string

        imageView.image = image

        setNeedsLayout()
    }
}

/// Layout
extension PromoTableListContentView {

    public override func layoutSubviews() {
        super.layoutSubviews()

        var xOffset = 0.0
        if !imageView.isHidden {
            let imageSize = imageView.image?.size ?? .zero
            let scale = imageSize.height / imageSize.width
            imageView.frame.size = CGSize(width: bounds.height * scale, height: bounds.height)
            if let promoView = self.promoView {
                let radius = promoView.cornerRadius - promoView.contentPadding.top
                imageView.layer.cornerRadius = max(0, radius)
            }
            xOffset = imageView.frame.maxX + (promoView?.contentPadding.left ?? 0.0)
        }

        let size = bounds.size
        var labelSize = label.sizeThatFits(size)
        labelSize.width = min(size.width, labelSize.width) - xOffset
        labelSize.height = min(size.height, labelSize.height)
        label.frame.size = labelSize
        label.frame.origin.x = xOffset
        label.frame.origin.y = (frame.height - label.frame.height) * 0.5
    }
}
