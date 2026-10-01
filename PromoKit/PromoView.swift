//
//  PromoView.swift
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

/// The size of the close button displayed on the promo view
@objc(PMKPromoViewCloseButtonSize)
public enum PromoViewCloseButtonSize: Int {
    case small  /// A small `xmark` icon (13pt)
    case large  /// A large `xmark.circle.fill` icon (17pt)
}

/// Receives provider resolution, display, and interaction updates from a promo view.
@objc(PMKPromoViewDelegate)
public protocol PromoViewDelegate: NSObjectProtocol {

    /// Called when a reload finds content, before that content is added to the view.
    /// Use this to decide whether to attach a promo view that was loaded while detached.
    /// - Parameters:
    ///   - promoView: The promo view that ran the reload
    ///   - provider: The provider that was resolved
    @objc optional func promoView(_ promoView: PromoView, didResolveProvider provider: PromoProvider)

    /// Called when a reload finds no replacement content.
    /// A failed refresh can retain previously displayed content; inspect `contentView` before hiding the view.
    /// - Parameter promoView: The promo view that ran the reload
    @objc optional func promoViewDidFailToResolveProvider(_ promoView: PromoView)

    /// Called when a provider is displaying its content, including when that
    /// content's preferred size changes. Use this to remeasure and lay out the promo.
    /// - Parameters:
    ///   - promoView: The promo view hosting the provider
    ///   - provider: The provider displaying content
    @objc optional func promoView(_ promoView: PromoView, didUpdateProvider provider: PromoProvider)

    /// Called after `promoViewDidFailToResolveProvider` when a reload finds no replacement content.
    /// Previously displayed content may remain available in `contentView`.
    /// - Parameter promoView: The promo view in which the failure occurred
    @objc optional func promoViewProviderFetchFailed(_ promoView: PromoView)

    /// The user tapped the close button displayed next to the promo view
    /// - Parameters:
    ///   - promoView: The promo view that owns the close button
    @objc optional func promoViewProviderDidTapCloseButton(_ promoView: PromoView)
}

/// Displays content from providers in priority order, falling back when a provider
/// has no content or cannot be fetched under the current network conditions.
@objc(PMKPromoView)
public class PromoView: UIControl {

    // MARK: - Public Properties

    /// The delegate for this promo view
    @objc public weak var delegate: PromoViewDelegate?

    /// The view controller hosting this promo view
    @objc public weak var rootViewController: UIViewController?

    /// The displayed content view, or `nil` when no content is currently installed.
    public var contentView: PromoContentView?

    /// The currently applied corner radius. Assigning sets the fallback used when providers do not override it.
    /// The default fallback is 20 points.
    public var cornerRadius: CGFloat {
        get { backgroundView.layer.cornerRadius }
        set {
            defaultCornerRadius = newValue
            updateCornerRadius()
        }
    }
    private var defaultCornerRadius: CGFloat = 20.0

    /// Whether a close button is shown to the right of the promo, or above when space is limited.
    /// Defaults to `false`.
    @objc public var showCloseButton: Bool = false {
        didSet {
            guard #available(iOS 13.0, *) else { return }
            updateCloseButtonVisibility()
        }
    }

    /// The close button's spoken label. Hosts can supply their localized wording.
    @objc public var closeButtonAccessibilityLabel: String = NSLocalizedString("Close", comment: "Dismiss a promotional card") {
        didSet { closeButton?.accessibilityLabel = closeButtonAccessibilityLabel }
    }

    /// The size of the close button (Default is small)
    public var closeButtonSize: PromoViewCloseButtonSize = .small {
        didSet {
            guard #available(iOS 13.0, *) else { return }
            configureCloseButton()
            setNeedsLayout()
        }
    }

    /// The background view displayed behind the content view
    @objc public let backgroundView: UIView = UIView()

    private var defaultBackgroundColor: UIColor?
    private var appliedProviderBackgroundColor: UIColor?

    /// The padding used when the provider does not supply its own.
    /// Initialized from the view's `layoutMargins`.
    public var defaultContentPadding: UIEdgeInsets = .zero

    /// The padding measured from the current content view's frame, or zero when no content view is installed.
    public var contentPadding: UIEdgeInsets {
        guard let contentFrame = contentView?.frame else { return .zero }
        return UIEdgeInsets(top: contentFrame.minY, left: contentFrame.minX,
                            bottom: frame.height - contentFrame.maxY, right: frame.width - contentFrame.maxX)
    }

    /// The promo providers in caller-specified priority order, highest priority first.
    /// Assigning a new value triggers `reload()` automatically when `reloadsAutomatically` is `true`.
    /// Removing the selected provider also removes its displayed content.
    @objc public var providers: [PromoProvider]? {
        get { providerCoordinator.providers }
        set {
            if providerCoordinator.isFetching,
               providerCoordinator.queryingProvider.map({ querying in
                   newValue?.contains(where: { $0 === querying }) == true
               }) != true {
                providerCoordinator.cancelFetch()
                setIsLoading(false)
            }
            providerCoordinator.providers = newValue
            if let previous = providerCoordinator.currentProvider,
               newValue?.contains(where: { $0 === previous }) != true {
                providerCoordinator.currentProvider = nil
                providerDidChange(nil)
            }
            if reloadsAutomatically { reload() }
        }
    }

    /// Whether assigning `providers` starts a reload. Defaults to `true`.
    /// Set to `false` to configure providers before calling `reload()` explicitly.
    @objc public var reloadsAutomatically: Bool = true

    /// The most recently selected provider, read-only to hosts.
    /// It remains selected while a size refresh replaces its content.
    @objc public internal(set) var currentProvider: PromoProvider? {
        get { providerCoordinator.currentProvider }
        set { providerCoordinator.currentProvider = newValue }
    }

    /// The minimum retry interval after a failed provider fetch. Defaults to 30 seconds.
    /// Calling `reload()` clears the fetch history used to enforce this interval.
    public var providerRetryInterval: TimeInterval {
        get { providerCoordinator.retryInterval }
        set { providerCoordinator.retryInterval = newValue }
    }

    /// The maximum time to wait for a provider fetch before falling through to the next provider.
    /// Set this to `0` to disable timeouts. Default is 15 seconds.
    public var providerFetchTimeout: TimeInterval {
        get { providerCoordinator.fetchTimeout }
        set { providerCoordinator.fetchTimeout = newValue }
    }

    /// A shared operation queue that providers may use to perform background processing (ie, data parsing or image decoding)
    public var backgroundQueue: OperationQueue {
        PromoView.sharedBackgroundQueue
    }

    /// Whether the first loading transition may animate when animation is requested.
    /// Set to `false` to show the initial placeholder immediately. Later transitions
    /// follow the `animated` argument passed to `setIsLoading`.
    @objc public var animatesInitialLoadingState: Bool = true

    /// Whether the loading spinner is shown. Assigning changes its visibility without animation.
    public var isLoading: Bool {
        get { _isLoading }
        set { setIsLoading(newValue, animated: false) }
    }
    private var _isLoading: Bool = false
    private var hasPresentedLoadingState = false

    /// When visible, the amount of vertical or horizontal spacing between the promo view and close button
    public var closeButtonSpacing = CGSize(width: 6.0, height: 4.0) {
        didSet { setNeedsLayout() }
    }

    /// The close button's size plus its spacing, or zero when the button is hidden.
    public var closeButtonOffset: CGSize {
        guard let closeButton, showCloseButton else { return .zero }
        return CGSize(width: closeButtonSpacing.width + closeButton.frame.width,
                      height: closeButtonSpacing.height + closeButton.frame.height)
    }

    /// The promo's bounds size plus `closeButtonOffset` in both dimensions.
    /// This reserves space for either placement of the visible close button.
    public var totalBoundsSize: CGSize {
        guard let closeButton, showCloseButton else { return bounds.size }
        return CGSize(width: bounds.width + closeButtonSpacing.width + closeButton.frame.width,
                      height: bounds.height + closeButtonSpacing.height + closeButton.frame.height)
    }

    /// A separate container view that is used to play an interactive animation when tapped.
    private let containerView = UIView()

    public override var frame: CGRect {
        didSet { updateContainerSizeIfNeeded() }
    }

    public override var bounds: CGRect {
        didSet { updateContainerSizeIfNeeded() }
    }

    private var lastObservedSize: CGSize = .zero
    private var isConfigured = false

    private func updateContainerSizeIfNeeded() {
        guard isConfigured, lastObservedSize != bounds.size else { return }
        let oldSize = lastObservedSize
        lastObservedSize = bounds.size
        let transform = containerView.transform
        containerView.transform = .identity
        containerView.frame = bounds
        backgroundView.frame = containerView.bounds
        containerView.transform = transform
        refreshCurrentProviderIfNeeded(oldSize: oldSize)
    }

    // MARK: - Private Properties

    /// Whether the current press permits the interaction animation.
    private var canPlayTapAnimation: Bool = true

    /// Track if the view is zoomed to avoid doubling up on animations
    private var isZoomed: Bool = false

    /// Whether the current press has been canceled by the provider or a content replacement.
    private var isInteractionCancelled: Bool = false

    /// A press belongs to the provider that received its touch-down.
    private weak var interactionProvider: PromoProvider?

    /// A coordinator for determining the current provider
    private lazy var providerCoordinator: PromoProviderCoordinator = {
        PromoProviderCoordinator(promoView: self)
    }()

    /// The store for recycled content view objects
    private var queuedContentViews = [ObjectIdentifier: [PromoContentView]]()

    /// An operation queue shared between all promo views that allow background processing of its fetched results
    private static var sharedBackgroundQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "dev.tim.PromoKit.MediaQueue"
        operationQueue.maxConcurrentOperationCount = 1
        // Keep media processing from competing with main-thread interactions.
        operationQueue.qualityOfService = .utility
        return operationQueue
    }()

    /// An optional loading spinner view that can be shown by the providers while they load their content
    private var spinnerView: UIActivityIndicatorView?

    /// The close button displayed at the top-right corner outside the view bounds
    private var closeButton: UIButton?

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
        super.init(frame: frame)

        // Allow close button to render outside bounds
        clipsToBounds = false

        // Configure default values
        self.defaultContentPadding = self.layoutMargins

        // Background view
        if #available(iOS 13.0, *) {
            backgroundView.backgroundColor = .secondarySystemBackground
            backgroundView.layer.cornerCurve = .continuous
        } else {
            backgroundView.backgroundColor = .init(white: 0.2, alpha: 1.0)
        }
        backgroundView.layer.cornerRadius = 20.0

        // Configure views
        containerView.isUserInteractionEnabled = true
        containerView.addSubview(backgroundView)
        addSubview(containerView)

        // Coordinator changes
        providerCoordinator.providerUpdatedHandler = { [weak self] provider in
            guard let self else { return }
            let generation = self.providerCoordinator.fetchGeneration
            // Let hosts decide whether to attach the view before composing content.
            if let provider {
                self.delegate?.promoView?(self, didResolveProvider: provider)
            } else {
                // Finish cleanup before a failure callback can start another reload.
                self.setIsLoading(false)
                self.providerDidChange(nil)
                guard self.providerCoordinator.fetchGeneration == generation else { return }
                // Empty or ineligible provider lists use the same failure callbacks as exhausted fetches.
                self.delegate?.promoViewDidFailToResolveProvider?(self)
                self.delegate?.promoViewProviderFetchFailed?(self)
                return
            }
            guard self.providerCoordinator.fetchGeneration == generation else { return }
            if let provider, self.currentProvider !== provider { return }
            self.providerDidChange(provider)
        }
        providerCoordinator.providerFetchFailedHandler = { [weak self] in
            guard let self else { return }
            // A size refresh removes the old card while retaining its provider
            // for further size changes. Clear that selection if the refresh fails.
            if self.contentView == nil { self.currentProvider = nil }
            self.setIsLoading(false)
            self.delegate?.promoViewDidFailToResolveProvider?(self)
            self.delegate?.promoViewProviderFetchFailed?(self)
        }
        isConfigured = true
        updateContainerSizeIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - View Sizing & Layout

extension PromoView {

    /// Shows an initial placeholder when attached without selected content or an active fetch.
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else { return }

        // Preserve content and loading state established before attachment.
        if currentProvider == nil && !providerCoordinator.isFetching {
            setIsLoading(true, animated: true)
        }
    }

    /// Returns the selected provider's preferred size, including content padding.
    /// Before resolution, uses the first declared provider; without providers, returns the current frame size.
    /// - Parameter size: The available outer size, including content padding.
    /// - Returns: The preferred outer size.
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let provider = currentProvider ?? providers?.first else {
            return frame.size
        }
        return sizeThatFits(size, for: provider)
    }

    /// Measures using the first provider whose concrete class matches `providerClass`.
    /// Falls back to `sizeThatFits(_:)` when the class is omitted or no provider matches.
    /// - Parameters:
    ///   - size: The size of the outer container in which this view needs to fit.
    ///   - providerClass: The class type of the provider in the list of active providers to use.
    public func sizeThatFits(_ size: CGSize, providerClass: AnyClass?) -> CGSize {
        if let providerClass,
           let provider = providerCoordinator.providerForClass(providerClass) {
            return sizeThatFits(size, for: provider)
        }
        return sizeThatFits(size)
    }

    /// Measures a provider or its displayed content view, adding the host padding.
    private func sizeThatFits(_ size: CGSize, for provider: PromoProvider) -> CGSize {
        // Remove the padding from fitting size to calculate the frame size
        var contentSize = size
        let padding = provider.contentPadding?(for: self) ?? defaultContentPadding
        contentSize.width -= padding.left + padding.right
        contentSize.height -= padding.top + padding.bottom

        // If the provider is visible on screen, use the content view to calculate accurate sizing
        var preferredsize = CGSize.zero
        if provider === currentProvider, let contentView, contentView.wantsSizingControl {
            preferredsize = contentView.sizeThatFits(contentSize)
        }

        // If we weren't able to fetch a size from the content view, defer back to the provider
        if preferredsize == .zero {
            preferredsize = provider.preferredContentSize?(fittingSize: contentSize, for: self) ?? contentSize
        }

        // Add the padding back in
        preferredsize.width += padding.left + padding.right
        preferredsize.height += padding.top + padding.bottom

        return preferredsize
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateContainerSizeIfNeeded()

        // Set the content view to be inset over the background view
        let contentPadding = contentPadding(for: currentProvider)
        contentView?.frame = bounds.inset(by: contentPadding).integral

        // Update the corner radius
        updateCornerRadius()

        // Update the spinner's layout and appearance.
        refreshSpinnerView()

        // Layout the close button
        layoutCloseButton()
    }

    /// Returns the content padding to apply for the given provider, falling back to `defaultContentPadding`.
    private func contentPadding(for provider: PromoProvider? = nil) -> UIEdgeInsets {
        let provider = provider ?? currentProvider ?? nil
        var contentPadding = self.defaultContentPadding
        if let providerPadding = provider?.contentPadding?(for: self) {
            contentPadding = providerPadding
        }
        return contentPadding
    }

    /// Applies the provider's corner radius or the host's configured fallback.
    private func updateCornerRadius(for provider: PromoProvider? = nil) {
        let provider = provider ?? currentProvider ?? nil
        let contentPadding = contentPadding(for: provider)
        var cornerRadius = defaultCornerRadius
        if let providerCornerRadius = provider?.cornerRadius?(for: self, with: contentPadding) {
            cornerRadius = providerCornerRadius
        }
        backgroundView.layer.cornerRadius = cornerRadius
    }
}

// MARK: - Fetching Providers

extension PromoView {

    /// Cancels pending resolution, clears fetch history, and starts from the highest-priority eligible provider.
    /// Existing content can remain visible until a replacement is selected. Providers' own state is not reset.
    ///
    /// The view may be detached while loading. Set its bounds before fetching size-sensitive content,
    /// and supply `rootViewController` for providers that present UI. Use the resolution callbacks
    /// to decide whether to attach the view after loading.
    @objc public func reload() {
        if providerCoordinator.isFetching {
            providerCoordinator.cancelFetch()
        }

        // Clear the coordinator's previous state
        providerCoordinator.reset()

        // Start fetching the best provider
        providerCoordinator.fetchBestProvider()
    }

    /// Calls `reload()` only when no provider is on display and no fetch is currently
    /// running. Safe to invoke from layout passes (e.g. `viewDidLayoutSubviews`) without
    /// interrupting an in-progress reload.
    public func reloadIfNeeded() {
        guard currentProvider == nil, !providerCoordinator.isFetching else { return }
        reload()
    }

    /// Replaces the current provider's content view using its existing data, without fetching again.
    public func reloadContentView() {
        providerDidChange(currentProvider)
    }

    /// Called by the coordinator when a new provider has been selected or cleared.
    /// Reclaims the previous content view and displays the new one, if any.
    private func providerDidChange(_ provider: PromoProvider?) {
        // Preserve direct host customization of the public background view.
        if appliedProviderBackgroundColor == nil || backgroundView.backgroundColor != appliedProviderBackgroundColor {
            defaultBackgroundColor = backgroundView.backgroundColor
        }
        appliedProviderBackgroundColor = provider?.backgroundColor ?? nil
        backgroundView.backgroundColor = appliedProviderBackgroundColor ?? defaultBackgroundColor

        // Display the new content
        if let provider {
            reclaimCurrentContentView()
            displayNewProvider(provider)
        } else { // Remove anything
            reclaimCurrentContentView()
            updateCornerRadius()
        }
    }

    /// Refreshes size-sensitive content, including an initial request still in flight.
    private func refreshCurrentProviderIfNeeded(oldSize: CGSize) {
        // Before the first resolution, resize the pending request instead.
        guard let provider = currentProvider ?? providerCoordinator.queryingProvider,
              provider.needsReloadOnSizeChange ?? false else { return }

        // Providers can keep their content when the size change does not affect it.
        if let shouldReload = provider.shouldReloadForSizeChange?(from: oldSize, to: bounds.size),
           !shouldReload {
            return
        }

        // Remove stale content only when a new fetch starts; a throttled refresh keeps it.
        // Size-invalid content disappears immediately without a fade.
        providerCoordinator.fetchBestProvider(from: provider) { [weak self] in
            self?.reclaimCurrentContentView(animated: false)
            self?.setIsLoading(true, animated: false)
        }
    }
}

// MARK: - Displaying Content

extension PromoView {

    /// Returns a pooled content view of the requested class, or creates one for this host.
    public func dequeueContentView<T: PromoContentView>(for contentViewClass: T.Type) -> T {
        // Fetch the first available content view from the store
        let contentViewIdentifier = ObjectIdentifier(contentViewClass)
        if var views = queuedContentViews[contentViewIdentifier],
           let contentView = views.first as? T {
            views.removeFirst()
            queuedContentViews[contentViewIdentifier] = views
            return contentView
        }

        // Instantiate the view and return it.
        return contentViewClass.init(promoView: self)
    }

    /// Removes and resets the current content view, optionally fading a snapshot while the view is pooled.
    private func reclaimCurrentContentView(animated: Bool = true) {
        if interactionProvider != nil { cancelTapInteraction() }
        guard let contentView else { return }

        // Animate a snapshot so the content view can be reused immediately.
        if animated, let snapshot = contentView.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = contentView.frame
            containerView.addSubview(snapshot)
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
        let contentViewIdentifier = ObjectIdentifier(type(of: contentView))
        if var views = self.queuedContentViews[contentViewIdentifier] {
            views.append(contentView)
            self.queuedContentViews[contentViewIdentifier] = views
        } else {
            self.queuedContentViews[contentViewIdentifier] = [contentView]
        }

        self.contentView = nil
    }

    /// Asks the provider to configure a content view, adds it to the hierarchy, and animates it in.
    private func displayNewProvider(_ provider: PromoProvider) {
        // If we were loading, hide the spinner view
        setIsLoading(false, animated: true)

        // Fetch a new view from the provider
        self.contentView = provider.contentView(for: self)
        self.containerView.addSubview(contentView!)

        // Delegates can start a new reload or resize while handling this callback.
        let generation = providerCoordinator.fetchGeneration
        let displayedContent = contentView
        delegate?.promoView?(self, didUpdateProvider: provider)
        guard providerCoordinator.fetchGeneration == generation,
              currentProvider === provider, contentView === displayedContent else { return }

        // Layout the content view
        let contentPadding = contentPadding(for: provider)
        contentView?.frame = bounds.inset(by: contentPadding).integral

        // Animate it fading in
        contentView?.alpha = 0.0
        UIView.animate(withDuration: 0.25) {
            self.contentView?.alpha = 1.0
            self.updateCornerRadius(for: provider)
            self.layoutCloseButton()
        }
    }
}

// MARK: - Loading Spinner

extension PromoView {

    /// The height the promo view needs to exceed before it'll swap to the large spinner
    static private let largeSpinnerRequiredHeight = 100.0

    /// Shows or hides the loading spinner without removing the current content view.
    /// - Parameters:
    ///   - isLoading: Whether the spinner should be visible or not.
    ///   - animated: Whether the loading animation is animated or not.
    public func setIsLoading(_ isLoading: Bool, animated: Bool = false) {
        guard isLoading != _isLoading else { return }

        let shouldAnimate = animated && (!isLoading || hasPresentedLoadingState || animatesInitialLoadingState)
        _isLoading = isLoading
        if isLoading { hasPresentedLoadingState = true }

        // Create the spinner view and configure it to our current environment.
        if isLoading {
            if spinnerView == nil {
                spinnerView = UIActivityIndicatorView(style: .medium)
                insertSubview(spinnerView!, aboveSubview: backgroundView)
            }
            spinnerView?.startAnimating()
        }

        // Keep the animation closures bound to this spinner instance.
        guard let spinnerView = self.spinnerView else { return }

        // Define closures that will either animate or occur instantly
        let scalingAnimationBlock: (() -> Void) = {
            spinnerView.transform = isLoading ?
                .identity :
                .identity.rotated(by: .pi).scaledBy(x: 0.01, y: 0.01)
        }

        let crossFadeAnimationBlock: (() -> Void) = {
            spinnerView.alpha = isLoading ? 1.0 : 0.0
        }

        let completionBlock: ((Bool) -> Void) = { _ in
            spinnerView.isHidden = !isLoading
        }

        // Set the initial state without inheriting an enclosing animation, such as rotation.
        UIView.performWithoutAnimation {
            spinnerView.isHidden = false
            spinnerView.layer.removeAllAnimations()
            spinnerView.transform = .identity
            refreshSpinnerView()
        }

        // If not animated, call these blocks right away
        if !shouldAnimate {
            scalingAnimationBlock()
            crossFadeAnimationBlock()
            completionBlock(true)
            return
        }

        // Set the animation's starting values without implicit animations.
        UIView.performWithoutAnimation {
            spinnerView.transform = isLoading ? .identity.rotated(by: .pi).scaledBy(x: 0.01, y: 0.01) : .identity
            spinnerView.alpha = isLoading ? 0.0 : 1.0
        }
        UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: [],
                       animations: scalingAnimationBlock, completion: completionBlock)
        UIView.animate(withDuration: 0.2, delay: 0.0, options: [], animations: crossFadeAnimationBlock)
    }

    /// Repositions and resizes the spinner view to match the current promo view state.
    /// Updates the spinner color based on background brightness, and switches between
    /// small and large spinner styles depending on the view height.
    private func refreshSpinnerView() {
        guard let spinnerView else { return }

        // Update the spinner view's tint color depending on the brightness of the background view
        var isDarkMode = false
        var backgroundViewColor: UIColor? = backgroundView.backgroundColor
        if #available(iOS 13.0, *) {
            backgroundViewColor = backgroundView.backgroundColor?.resolvedColor(with: traitCollection)
        }

        // If the background color isn't nil or clear, calculate its greyscale brightness
        // https://gist.github.com/delputnam/2d80e7b4bd9363fd221d131e4cfdbd8f
        if let backgroundViewColor, backgroundViewColor != UIColor.clear {
            var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0
            backgroundViewColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
            let brightness =  ((red * 299) + (green * 587) + (blue * 114)) / 1000
            isDarkMode = brightness < 0.5
        } else {
            if #available(iOS 13.0, *) {
                isDarkMode = traitCollection.userInterfaceStyle == .dark
            }
        }

        // Change style and size immediately, while allowing the center to animate during rotation.
        UIView.performWithoutAnimation {
            spinnerView.color = isDarkMode ? .white : .gray

            // Keep the existing size while the spinner is disappearing.
            if isLoading {
                let useLargeSize = frame.height > PromoView.largeSpinnerRequiredHeight
                spinnerView.style = useLargeSize ? .large : .medium
            }
            spinnerView.sizeToFit()
        }

        // Position the spinner in the middle of the view
        spinnerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

// MARK: - Close Button

extension PromoView {

    /// Updates the visibility of the close button based on the showCloseButton property
    @available(iOS 13.0, *)
    private func updateCloseButtonVisibility() {
        if showCloseButton {
            if closeButton == nil {
                createCloseButton()
            }
            closeButton?.isHidden = false
        } else {
            closeButton?.isHidden = true
        }
    }

    /// Creates and configures the close button
    @available(iOS 13.0, *)
    private func createCloseButton() {
        let button = UIButton(type: .system)
        button.accessibilityLabel = closeButtonAccessibilityLabel
        button.accessibilityTraits.insert(.button)
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        addSubview(button)
        closeButton = button
        configureCloseButton()
    }

    /// Configures the close button appearance based on the current size setting
    @available(iOS 13.0, *)
    private func configureCloseButton() {
        guard let closeButton else { return }

        let image: UIImage?
        switch closeButtonSize {
        case .small:
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            image = UIImage(systemName: "xmark", withConfiguration: symbolConfig)
        case .large:
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
            image = UIImage(systemName: "xmark.circle.fill", withConfiguration: symbolConfig)
        }

        closeButton.setImage(image, for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.sizeToFit()
    }

    /// Lays out the close button to the right of the view, or above if there's no horizontal space
    private func layoutCloseButton() {
        guard let closeButton, !closeButton.isHidden else { return }

        let buttonSize = closeButton.bounds.size
        let spacing = closeButtonSpacing

        // Check available horizontal space to the right
        let availableRight = (superview?.bounds.width ?? .greatestFiniteMagnitude) - frame.maxX
        if availableRight >= buttonSize.width + spacing.width {
            // Position to the right of the view
            closeButton.frame.origin = CGPoint(x: bounds.maxX + spacing.width,
                                               y: cornerRadius * 0.4)
        } else {
            // Position above the view, aligned with the promo view's right edge
            var xPosition = bounds.maxX - (buttonSize.width + (cornerRadius * 0.4))

            // Keep the button within the superview's right edge.
            if let superview = superview {
                let buttonRightEdgeInSuperview = frame.minX + xPosition + buttonSize.width
                if buttonRightEdgeInSuperview > superview.bounds.width {
                    let overflow = buttonRightEdgeInSuperview - superview.bounds.width
                    xPosition -= (overflow + 8)
                }
            }

            closeButton.frame.origin = CGPoint(x: xPosition,
                                               y: -buttonSize.height - spacing.height)
        }
    }

    @objc private func closeButtonTapped() {
        delegate?.promoViewProviderDidTapCloseButton?(self)
    }

    /// Extends hit testing to include the close button which is positioned outside bounds
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let closeButton, !closeButton.isHidden {
            // Expand the close button's hit area for easier tapping
            let expandedFrame = closeButton.frame.insetBy(dx: -10, dy: -10)
            if expandedFrame.contains(point) {
                return true
            }
        }
        return super.point(inside: point, with: event)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        if let closeButton, !closeButton.isHidden {
            let expandedFrame = closeButton.frame.insetBy(dx: -10, dy: -10)
            if expandedFrame.contains(point) {
                return closeButton
            }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Interaction Animations

extension PromoView {

    /// Cancels the current press and removes its interaction animation.
    /// Further drag and activation callbacks are suppressed. The original provider receives
    /// `didCancelTap` when the touch ends or UIKit cancels it.
    /// - Parameter animated: Whether to animate the return to the unpressed appearance.
    public func cancelTapInteraction(animated: Bool = false) {
        setZoomed(false, animated: animated)
        isInteractionCancelled = true
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        interactionProvider = nil
        canPlayTapAnimation = true
        // Loading views do not start provider interactions.
        if isLoading {
            canPlayTapAnimation = false
            isInteractionCancelled = true
            return
        }

        // Reset the cancellation flag from the previous interaction
        isInteractionCancelled = false

        guard let provider = currentProvider, let touch = touches.first else { return }
        interactionProvider = provider
        provider.didTapDownInside?(promoView: self, with: touch)
        guard !isInteractionCancelled, currentProvider === provider else {
            cancelTapInteraction()
            return
        }

        canPlayTapAnimation = provider.shouldPlayInteractionAnimation?(for: self, with: touch) ?? true
        guard !isInteractionCancelled, currentProvider === provider else {
            cancelTapInteraction()
            return
        }
        if canPlayTapAnimation { setZoomed(true, animated: true) }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard !isInteractionCancelled, let touch = touches.first,
              let provider = interactionProvider, currentProvider === provider else { return }
        if canPlayTapAnimation {
            let zoomed = bounds.contains(touch.location(in: self))
            setZoomed(zoomed, animated: true)
        }
        provider.didDragInside?(promoView: self, with: touch)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        canPlayTapAnimation = true
        setZoomed(false, animated: true)
        let provider = interactionProvider
        interactionProvider = nil
        if let provider, let touch = touches.first {
            if !isInteractionCancelled, currentProvider === provider,
               !isLoading, bounds.contains(touch.location(in: self)) {
                provider.didTapUpInside?(promoView: self, with: touch)
            } else {
                provider.didCancelTap?(promoView: self, with: touch)
            }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        canPlayTapAnimation = true
        setZoomed(false, animated: true)
        let provider = interactionProvider
        interactionProvider = nil
        if let provider, let touch = touches.first {
            provider.didCancelTap?(promoView: self, with: touch)
        }
    }

    /// Applies or removes the subtle scale-down transform used for the tap press animation.
    /// - Parameters:
    ///   - zoomed: Whether the view should appear pressed in.
    ///   - animated: Whether the transition is animated.
    private func setZoomed(_ zoomed: Bool, animated: Bool = false) {
        guard isZoomed != zoomed else { return }
        isZoomed = zoomed
        UIView.animate(withDuration: animated ? 0.45 : 0.0,
                       delay: 0.0,
                       usingSpringWithDamping: 1.0,
                       initialSpringVelocity: 1.0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.containerView.transform = zoomed ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
        }
    }
}
