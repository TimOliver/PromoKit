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
@objc(PMKPromoListContentView)
public class PromoListContentView: UIView, PromoContentView {

    // MARK: - Public Properties

    /// A large title label displayed along the top of the view
    public let titleLabel = UILabel()

    /// An optional detail label displayed underneath the title label
    public let detailLabel = UILabel()

    // An optional image displayed horizontally along the leading edge of the view
    public let imageView = UIImageView()

    /// The reuse identifier associated with this particular instance
    public private(set) var reuseIdentifier: String

    /// Creates a new instance of a list content view.
    /// - Parameter reuseIdentifier: The reuse identifier used to fetch this instance from the promo view
    public required init(reuseIdentifier: String) {
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(imageView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Reset all of the view state when the content view is being recycled
    public func prepareForReuse() {
        // It is best practice to nil out all view content since these can contribute to
        // the overall memory footprint
        titleLabel.text = nil
        detailLabel.text = nil
        imageView.image = nil
    }

    /// Configures the list content view with the provided text and image data
    /// - Parameters:
    ///   - title: The text that will be displayed as the main title.
    ///   - detailText: The text optionally shown below the main title.
    ///   - image: The image optionally shown leading into the title.
    public func configure(title: String, detailText: String? = nil, image: UIImage? = nil) {
        titleLabel.text = title
        detailLabel.text = detailText
        imageView.image = image

        detailLabel.isHidden = (detailText == nil)
        imageView.isHidden = (image == nil)
    }
}
