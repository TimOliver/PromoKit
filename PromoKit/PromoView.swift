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
    public var contentView: PromoContentView?

    /// The corner radius of the promo view
    public var cornerRadius: CGFloat {
        set { backgroundView.layer.cornerRadius = newValue }
        get { backgroundView.layer.cornerRadius }
    }

    /// Whether a close button is shown on the trailing side of the ad view (Default is false)
    public var showCloseButton: Bool = false

    /// The background view displayed behind the content view
    private(set) public var backgroundView: UIView

    /// When providers don't specify their own insetting, the content insetting of the promo view is used instead
    /// The default value is the view's `layoutMargins`
    public var contentPadding: UIEdgeInsets = .zero

    /// The promo providers currently assigned to this promo view, sorted in order of priority.
    public var providers: [PromoProvider]? {
        set { providerCoordinator.providers = newValue; reload() }
        get { providerCoordinator.providers }
    }

    /// The current provider being displayed by this view
    public var currentProvider: PromoProvider? {
        set { providerCoordinator.currentProvider = newValue }
        get { providerCoordinator.currentProvider }
    }

    /// The retry interval to wait between failed online provider fetches (Default is 30 seconds)
    public var providerRetryInterval: TimeInterval {
        set { providerCoordinator.retryInterval = newValue }
        get { providerCoordinator.retryInterval }
    }

    // MARK: - Private Properties

    /// A coordinator for determining the current provider
    private let providerCoordinator = PromoProviderCoordinator()

    /// The store for recycled content view objects
    private var queuedContentViews = [ObjectIdentifier : Array<PromoContentView>]()

    /// If set, this can be used to know in advance the maximum size of the promo view, which can be used for image loading
    private var maximumContentSizes = [UIUserInterfaceSizeClass : CGSize]()

    // MARK: - View Creation

    /// Create a new promo view instance with a list of preconfigured providers.
    /// - Parameters:
    ///   - frame: The frame of the promo view
    ///   - providers: An array of providers, in order of priority to display.
    public convenience init(frame: CGRect, providers: [PromoProvider]) {
        self.init(frame: frame)
        self.providers = providers
    }

    /// Create a new promo view instance with the provided frame
    /// - Parameter frame: The frame of the promo view
    public override init(frame: CGRect) {
        // Background view
        backgroundView = UIView()
        if #available(iOS 13.0, *) {
            backgroundView.backgroundColor = .secondarySystemBackground
            backgroundView.layer.cornerCurve = .continuous
        } else {
            backgroundView.backgroundColor = .init(white: 0.2, alpha: 1.0)
        }

        // Class initialization
        super.init(frame: frame)

        // Configure views post creation
        addSubview(backgroundView)

        // Configure default values
        self.contentPadding = self.layoutMargins
        backgroundView.layer.cornerRadius = 15

        // Coordinator changes
        providerCoordinator.providerUpdatedHandler = { [weak self] provider in
            self?.providerDidChange(provider)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - View Sizing & Layout

extension PromoView {

    /// Optionally, promo views can be configured with maximum sizes that `sizeToFit` will stick to.
    /// This can be used to give certain providers that load image data a hint on what size images it should request.
    /// - Parameters:
    ///   - size: The maximum size in points (without insetting) that the content view may be.
    ///   - sizeClass: The size class (whether compact or regular) that this size is applied to.
    public func setMaximumContentSize(_ size: CGSize, for sizeClass: UIUserInterfaceSizeClass) {
        maximumContentSizes[sizeClass] = size
    }

    /// Returns the maximum size for the promo view's content for the requested size class.
    /// - Parameter sizeClass: The size class (compact or regular) for the requested size.
    /// - Returns: The requested size, or `.zero` if not set.
    public func maximumContentSize(for sizeClass: UIUserInterfaceSizeClass) -> CGSize {
        return maximumContentSizes[sizeClass] ?? .zero
    }

    /// Returns the most appropriate size this view should be when fitting into the provided container size.
    /// This will then be passed to the current provider object that can calculate the size itself, or forward it to a content view.
    /// - Parameter size: The size of the outer container that this promo view should size itself to fit (Including inset padding).
    /// - Returns: The most appropriate size this view should be to fit the container view
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return sizeThatFits(size, providerIdentifier: providers?.first?.identifier)
    }

    /// For cases where a single provider is representing a statically sized UI element (ie a fixed ad banner),
    /// this method may be used to forward all the sizing requests to that provider, with the expectation that the other
    /// providers will be able to dynamically size themselves to fit.
    /// - Parameters:
    ///   - size: The size of the outer container in which this view needs to fit.
    ///   - providerIdentifier: The identifier of the provider that should be used for this sizing calculation
    public func sizeThatFits(_ size: CGSize, providerIdentifier: String?) -> CGSize {
        // Check we have a valid provider that implements the sizing protocol method, or skip otherwise
        guard let providerIdentifier,
              let provider = providerCoordinator.providerForIdentifier(providerIdentifier) else {
            return frame.size
        }

        // Remove the padding from fitting size to calculate the frame size
        var contentSize = size
        let padding = provider.contentPadding?(for: self) ?? .zero
        contentSize.width -= padding.left + padding.right
        contentSize.height -= padding.top + padding.bottom

        // Add the padding back in
        var preferredsize = provider.preferredContentSize?(fittingSize: contentSize, for: self) ?? contentSize
        preferredsize.width += padding.left + padding.right
        preferredsize.height += padding.top + padding.bottom

        return preferredsize
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil, !(providers?.isEmpty ?? true) else { return }
        reload()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Set the background to match the
        backgroundView.frame = bounds

        // Set the content view to be inset over the background view
        var contentFrame = bounds.inset(by: contentPadding)
        if let padding = currentProvider?.contentPadding?(for: self) {
            contentFrame = bounds.inset(by: padding)
        }
        contentView?.frame = CGRectIntegral(contentFrame)
    }
}

// MARK: - Loading Content

extension PromoView {
    /// Clears all state and starts a new fetch of all providers from scratch.
    public func reload() {
        guard !providerCoordinator.isFetching else { return }

        // Clear the coordinator's previous state
        providerCoordinator.reset()

        // Start fetching the best provider
        providerCoordinator.fetchBestProvider()
    }

    // Callback used to update the promo view when the coordinator detects anew provider
    private func providerDidChange(_ provider: PromoProvider?) {
        // Display the new content
        if let provider {
            prepareToDisplayProvider(provider)
            displayNewProvider(provider)
        } else { // Remove anything
            reclaimCurrentContentView()
        }
    }
}

// MARK: - Displaying Content

extension PromoView {

    /// Dequeues and returns a previously created content view with the same identifier,
    /// if available.
    public func dequeueContentView<T: PromoContentView>(for contentViewClass: T.Type) -> T {
        // Fetch the first available content view from the store
        if var views = queuedContentViews[ObjectIdentifier(contentViewClass.self)],
           let contentView = views.first as? T {
            views.removeFirst()
            return contentView
        }

        // Instantiate the view and return it.
        return contentViewClass.init(promoView: self)
    }

    // Clean up the current content view if there is one
    private func reclaimCurrentContentView() {
        guard let contentView else { return }

        // Fade the current content view out
        if let snapshot = contentView.snapshotView(afterScreenUpdates: true) {
            snapshot.frame = contentView.frame
            addSubview(snapshot)
            UIView.animate(withDuration: 0.25) {
                snapshot.alpha = 0.0
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }

        // Remove from view, and clean it up
        contentView.removeFromSuperview()
        contentView.prepareForReuse()

        // Add it back to the pool
        if var views = self.queuedContentViews[ObjectIdentifier(contentView.self)] {
            views.append(contentView)
        } else {
            self.queuedContentViews[ObjectIdentifier(contentView.self)] = [contentView]
        }

        self.contentView = nil
    }

    // Set everything up to display the new provider
    private func prepareToDisplayProvider(_ provider: PromoProvider) {
        reclaimCurrentContentView()
    }

    // Get the provider to generate and configure its view content, and then display it
    private func displayNewProvider(_ provider: PromoProvider) {
        // Fetch a new view from the provider
        self.contentView = provider.contentView(for: self)
        self.addSubview(contentView!)
        setNeedsLayout()

        // Animate it fading in
        contentView?.alpha = 0.0
        UIView.animate(withDuration: 0.25) {
            self.contentView?.alpha = 1.0
        }
    }
}
