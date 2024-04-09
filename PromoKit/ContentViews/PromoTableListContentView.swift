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
        var titleFont = UIFont.preferredFont(forTextStyle: .largeTitle)
        if let newDescriptor = titleFont.fontDescriptor.withSymbolicTraits(.traitBold) {
            titleFont = UIFont(descriptor: newDescriptor, size: titleFont.pointSize)
        }

        let string = NSMutableAttributedString(string: title, attributes: [.font : titleFont]);
        if let detailText {
            string.append(NSAttributedString(string: "\n"))
            string.append(NSAttributedString(string: detailText, attributes: [.font : UIFont.preferredFont(forTextStyle: .title1)]))
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

        let size = bounds.size
        var labelSize = label.sizeThatFits(size)
        labelSize.width = min(size.width, labelSize.width)
        labelSize.height = min(size.height, labelSize.height)
        label.frame.size = labelSize

    }

}
