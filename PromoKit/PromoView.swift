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

    /// The dictionary tracking which identifiers map to which classes
    private var registeredContentViewClasses = [String : PromoContentView.Type]()

    /// The store for recycled content view objects
    private var queuedContentViews = [String : Array<PromoContentView>]()

    // MARK: - View Creation

    public convenience init(frame: CGRect, providers: [PromoProvider]) {
        self.init(frame: frame)
        self.providers = providers
    }

    public override init(frame: CGRect) {
        // Background view
        backgroundView = UIView()
        if #available(iOS 13.0, *) {
            backgroundView.backgroundColor = .secondarySystemBackground
            backgroundView.layer.cornerCurve = .continuous
        } else {
            backgroundView.backgroundColor = .init(white: 0.2, alpha: 1.0)
        }
        backgroundView.layer.cornerRadius = 15
        super.init(frame: frame)
        addSubview(backgroundView)

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
              let provider = providerCoordinator.providerForIdentifier(providerIdentifier),
              var size = provider.preferredContentSize?(for: self) else {
            return frame.size
        }

        // Add the padding from the provider
        if let padding = provider.contentPadding?(for: self) {
            size.width += padding.left + padding.right
            size.height += padding.top + padding.bottom
        }
        return size
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
        var contentFrame = bounds
        if let padding = currentProvider?.contentPadding?(for: self) {
            contentFrame = contentFrame.inset(by: padding)
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
    /// Registers a content view against an associated reuse identifier.
    /// Subsequent calls to the dequeue method will use this information to recycle or generate
    /// a new content view for it.
    public func registerContentViewClass(_ contentViewClass: PromoContentView.Type, for reuseIdentifier: String) {
        registeredContentViewClasses[reuseIdentifier] = contentViewClass
    }

    /// Dequeues and returns a previously created content view with the same identifier,
    /// if available.
    public func dequeueContentView(with reuseIdentifier: String) -> PromoContentView {
        // Fetch the first available content view from the store
        if var views = queuedContentViews[reuseIdentifier],
           let contentView = views.first {
            views.removeFirst()
            return contentView
        }

        // Create a new content view from scratch
        // Fetch the class from the registered list
        guard let viewClass = registeredContentViewClasses[reuseIdentifier] else {
            fatalError("PromoView: \(reuseIdentifier) wasn't registered.")
        }
        
        // Instantiate the view and return it.
        return viewClass.init(reuseIdentifier: reuseIdentifier)
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
        if var views = self.queuedContentViews[contentView.reuseIdentifier] {
            views.append(contentView)
        } else {
            self.queuedContentViews[contentView.reuseIdentifier] = [contentView]
        }

        self.contentView = nil
    }

    // Set everything up to display the new provider
    private func prepareToDisplayProvider(_ provider: PromoProvider) {
        provider.registerContentViewClasses(for: self)
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
