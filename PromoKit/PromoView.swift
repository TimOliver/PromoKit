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
    
    // MARK: - View Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
    }
}
