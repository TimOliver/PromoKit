//
//  PromoView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 29/1/2024.
//

import UIKit

/// A UI component for displaying promotional or advertising content from a variety of sources,
/// determined and updated dynamically at runtime.
/// It can be used to show a regular set of content, such as ads, but allow for higher priority
/// content, such as app news announcements to automatically override and display instead.
/// It also has fallback mechanisms for displaying alternative content if there is no internet connection.
@objc(PMKPromoView)
public class PromoView: UIView {

    // MARK: - Public Properties -

    /// The content view from the currently active promo provider
    public var contentView: UIView?

    /// The corner radius of the promo view
    public var cornerRadius: CGFloat {
        set { backgroundView.layer.cornerRadius = newValue }
        get { backgroundView.layer.cornerRadius }
    }

    /// Whether a close button is shown on the trailing side of the ad view (Default is false)
    public var showCloseButton: Bool = false

    /// The background view displayed behind the content view
    private(set) public var backgroundView: UIView

    /// The promo providers currently assigned to this promo view, sorted in order of priority.
    public var providers: [PromoProvider]?

    /// The currently displayed provider
    private(set) public var currentProvider: PromoProvider?

    // MARK: - View Creation

    public convenience init(frame: CGRect, providers: [PromoProvider]) {
        self.init(frame: frame)
        self.providers = providers
    }

    public override init(frame: CGRect) {
        backgroundView = UIView()
        if #available(iOS 13.0, *) {
            backgroundView.backgroundColor = .secondarySystemBackground
        } else {
            backgroundView.backgroundColor = .init(white: 0.2, alpha: 1.0)
        }
        super.init(frame: frame)
        addSubview(backgroundView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Sizing

    /// Returns the most appropriate size this view should be when fitting into the provided container size.
    /// This will then be passed to the current provider object that can calculate the size itself, or forward it to a content view.
    /// - Parameter size: The size of the outer container that this promo view should size itself to fit (Including inset padding).
    /// - Returns: The most appropriate size this view should be to fit the container view
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return sizeThatFits(size, providerIdentifier: currentProvider?.identifier ?? nil)
    }

    /// For cases where a single provider is representing a statically sized UI element (ie a fixed ad banner),
    /// this method may be used to forward all the sizing requests to that provider, with the expectation that the other
    /// providers will be able to dynamically size themselves to fit.
    /// - Parameters:
    ///   - size: The size of the outer container in which this view needs to fit.
    ///   - providerIdentifier: The identifier of the provider that should be used for this sizing calculation
    public func sizeThatFits(_ size: CGSize, providerIdentifier: String?) -> CGSize {
        .zero
    }

    // MARK: - View Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
    }
}
