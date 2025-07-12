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

/// A delegate object that external objects can use to receive updates from this promo view.
@objc(PMKPromoViewDelegate)
public protocol PromoViewDelegate: NSObjectProtocol {

    /// Called when a new provider has successfully been fetched and is now displaying
    /// its content. This can be used to trigger new layout passes if needed.
    /// - Parameters:
    ///   - promoView: The promo view hosting the provider
    ///   - provider: The provider that was successfully loaded
    @objc optional func promoView(_ promoView: PromoView, didUpdateProvider provider: PromoProvider)

    /// A fetch completely failed and there is no content to display.
    /// Use this method to hide the promo view if needed.
    /// - Parameters:
    ///   - promoView: The promo view in which the error occurred
    ///   - error: The error that occurred
    @objc optional func promoViewProviderFetchFailed(_ promoView: PromoView)
}

/// A UI component for displaying promotional or advertising content from a variety of sources,
/// determined and updated dynamically at runtime.
/// It can be used to show a regular set of content, such as ads, but allow for higher priority
/// content, such as app news announcements to automatically override and display instead.
/// It also has fallback mechanisms for displaying alternative content if there is no internet connection.
@objc(PMKPromoView)
public class PromoView: UIControl {

    // MARK: - Public Properties -

    /// The delegate for this promo view
    public weak var delegate: PromoViewDelegate?

    /// The view controller hosting this promo view
    public weak var rootViewController: UIViewController?

    /// The content view from the currently active promo provider
    public var contentView: PromoContentView?

    /// The corner radius of the promo view (Default is 20.0)
    public var cornerRadius: CGFloat {
        get { backgroundView.layer.cornerRadius }
        set { backgroundView.layer.cornerRadius = newValue }
    }

    /// Whether a close button is shown on the trailing side of the ad view (Default is false)
    public var showCloseButton: Bool = false

    /// The background view displayed behind the content view
    public let backgroundView: UIView = UIView()

    /// When providers don't specify their own insetting, the content insetting of the promo view is used instead
    /// The default value is the view's `layoutMargins`
    public var defaultContentPadding: UIEdgeInsets = .zero

    /// The current content padding, whether it's the default value, or the current one specified by the content view
    public var contentPadding: UIEdgeInsets {
        guard let contentFrame = contentView?.frame else { return .zero }
        return UIEdgeInsets(top: contentFrame.minY, left: contentFrame.minX,
                            bottom: frame.height - contentFrame.maxY, right: frame.width - contentFrame.maxX)
    }

    /// The promo providers currently assigned to this promo view, sorted in order of priority.
    public var providers: [PromoProvider]? {
        get { providerCoordinator.providers }
        set { providerCoordinator.providers = newValue; reload() }
    }

    /// The current provider being displayed by this view
    public var currentProvider: PromoProvider? {
        get { providerCoordinator.currentProvider }
        set { providerCoordinator.currentProvider = newValue }
    }

    /// The retry interval to wait between failed online provider fetches (Default is 30 seconds)
    public var providerRetryInterval: TimeInterval {
        get { providerCoordinator.retryInterval }
        set { providerCoordinator.retryInterval = newValue }
    }

    /// A shared operation queue that providers may use to perform background processing (ie, data parsing or image decoding)
    public var backgroundQueue: OperationQueue {
        PromoView.sharedBackgroundQueue
    }

    /// Shows a loading spinner view. This is used as a placeholder whenever a provider isn't being shown.
    public var isLoading: Bool {
        get { _isLoading }
        set { setIsLoading(newValue, animated: false) }
    }
    private var _isLoading: Bool = false

    /// A separate container view that is used to play an interactive animation when tapped.
    private let containerView = UIView()

    /// Changing the frame of this promo view
    public override var frame: CGRect {
        didSet {
            guard oldValue.size != frame.size else { return }

            // Because the 'transform' property influences view frames,
            // if a frame change happens mid animation, put the transform briefly back to handle it.
            // But don't touch the container view any other time.
            let transform = containerView.transform
            containerView.transform = .identity
            containerView.frame = bounds
            backgroundView.frame = containerView.bounds
            containerView.transform = transform

            // If the provider needs to refresh on a bounds change, do it now
            refreshCurrentProviderIfNeeded()
        }
    }

    // MARK: - Private Properties

    /// Track if a tap animation was invalid at the start to prevent it from starting mid-way
    private var canPlayTapAnimation: Bool = true

    /// Track if the view is zoomed to avoid doubling up on animations
    private var isZoomed: Bool = false

    /// Track if an in-progress gesture has been manually canceled
    private var isInteractionCancelled: Bool = false

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
        operationQueue.qualityOfService = .userInitiated
        return operationQueue
    }()

    /// An optional loading spinner view that can be shown by the providers while they load their content
    private var spinnerView: UIActivityIndicatorView?

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
        addSubview(containerView)

        containerView.addSubview(backgroundView)

        // Configure default values
        self.defaultContentPadding = self.layoutMargins
        backgroundView.layer.cornerRadius = 20

        // Coordinator changes
        providerCoordinator.providerUpdatedHandler = { [weak self] provider in
            self?.providerDidChange(provider)
        }
        providerCoordinator.providerFetchFailedHandler = { [weak self] in
            guard let self else { return }
            self.delegate?.promoViewProviderFetchFailed?(self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - View Sizing & Layout

extension PromoView {

    /// When the view moves to the superview, the loading spinner will be visible by default.
    /// This shows some placeholder content while giving the hosting app time to determine which providers it wishes to show.
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else { return }
        setIsLoading(true, animated: true)
    }

    /// Returns the most appropriate size this view should be when fitting into the provided container size.
    /// This will then be passed to the current provider object that can calculate the size itself, or forward it to a content view.
    /// - Parameter size: The size of the outer container that this promo view should size itself to fit (Including inset padding).
    /// - Returns: The most appropriate size this view should be to fit the container view
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        var providerClass: AnyClass?
        if let provider = currentProvider ?? providers?.first {
            providerClass = type(of: provider)
        }
        return sizeThatFits(size, providerClass: providerClass)
    }

    /// For cases where a single provider is representing a statically sized UI element (ie a fixed ad banner),
    /// this method may be used to forward all the sizing requests to that provider, with the expectation that the other
    /// providers will be able to dynamically size themselves to fit.
    /// - Parameters:
    ///   - size: The size of the outer container in which this view needs to fit.
    ///   - providerClass: The class type of the provider in the list of active providers to use.
    public func sizeThatFits(_ size: CGSize, providerClass: AnyClass?) -> CGSize {
        // Check we have a valid provider that implements the sizing protocol method, or skip otherwise
        guard let providerClass,
              let provider = providerCoordinator.providerForClass(providerClass) else {
            return frame.size
        }

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

        // Set the content view to be inset over the background view
        let contentPadding = contentPadding(for: currentProvider)
        contentView?.frame = bounds.inset(by: contentPadding).integral

        // Update the corner radius
        updateCornerRadius()

        // Layout the spinner view if the promo view is currently loading
        refreshSpinnerView()
    }

    private func contentPadding(for provider: PromoProvider? = nil) -> UIEdgeInsets {
        let provider = provider ?? currentProvider ?? nil
        var contentPadding = self.defaultContentPadding
        if let providerPadding = provider?.contentPadding?(for: self) {
            contentPadding = providerPadding
        }
        return contentPadding
    }

    private func updateCornerRadius(for provider: PromoProvider? = nil) {
        let provider = provider ?? currentProvider ?? nil
        let contentPadding = contentPadding(for: provider)
        var cornerRadius = self.cornerRadius
        if let providerCornerRadius = provider?.cornerRadius?(for: self, with: contentPadding) {
            cornerRadius = providerCornerRadius
        }
        backgroundView.layer.cornerRadius = cornerRadius
    }
}

// MARK: - Fetching Providers

extension PromoView {

    /// Clears all state and starts a new fetch of all providers from scratch.
    public func reload() {
        guard superview != nil, !providerCoordinator.isFetching else { return }

        // Clear the coordinator's previous state
        providerCoordinator.reset()

        // Start fetching the best provider
        providerCoordinator.fetchBestProvider()
    }

    /// Calls `reload()` but only if no provider has been selected yet.
    public func reloadIfNeeded() {
        guard currentProvider == nil else { return }
        reload()
    }

    /// Reloads the content view for the current provider. Providers may explicitly
    /// call this themselves if they detect their state changed, and the view needs to be reloaded.
    public func reloadContentView() {
        providerDidChange(currentProvider)
    }

    // Callback used to update the promo view when the coordinator detects anew provider
    private func providerDidChange(_ provider: PromoProvider?) {
        // Display the new content
        if let provider {
            reclaimCurrentContentView()
            displayNewProvider(provider)
        } else { // Remove anything
            reclaimCurrentContentView()
        }
    }

    /// Refresh the current provider if needed
    private func refreshCurrentProviderIfNeeded() {
        guard currentProvider?.needsReloadOnSizeChange ?? false else { return }
        providerCoordinator.fetchBestProvider(from: currentProvider)
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
        if let snapshot = contentView.snapshotView(afterScreenUpdates: false) {
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
        if var views = self.queuedContentViews[ObjectIdentifier(contentView.self)] {
            views.append(contentView)
        } else {
            self.queuedContentViews[ObjectIdentifier(contentView.self)] = [contentView]
        }

        self.contentView = nil
    }

    // Get the provider to generate and configure its view content, and then display it
    private func displayNewProvider(_ provider: PromoProvider) {
        // If we were loading, hide the spinner view
        setIsLoading(false, animated: true)

        // Fetch a new view from the provider
        self.contentView = provider.contentView(for: self)
        self.containerView.addSubview(contentView!)

        // Inform the delegate a new provider was fetched
        delegate?.promoView?(self, didUpdateProvider: provider)

        // Layout the content view
        let contentPadding = contentPadding(for: provider)
        contentView?.frame = bounds.inset(by: contentPadding).integral

        // Animate it fading in
        contentView?.alpha = 0.0
        UIView.animate(withDuration: 0.25) {
            self.contentView?.alpha = 1.0
            self.updateCornerRadius(for: provider)
        }
    }
}

// MARK: - Loading Spinner

extension PromoView {

    /// The height the promo view needs to exceed before it'll swap to the large spinner
    static private let largeSpinnerRequiredHeight = 100.0

    /// Hides the content view and shows a loading spinner.
    /// The spinner can optionally transition in and out with an animation
    /// - Parameters:
    ///   - isLoading: Whether the spinner should be visible or not.
    ///   - animated: Whether the loading animation is animated or not.
    public func setIsLoading(_ isLoading: Bool, animated: Bool = false) {
        guard isLoading != _isLoading else { return }

        _isLoading = isLoading

        // Create the spinner view and configure it to our current environment.
        if isLoading {
            if spinnerView == nil {
                spinnerView = UIActivityIndicatorView(style: .gray)
                insertSubview(spinnerView!, aboveSubview: backgroundView)
            }
            spinnerView?.startAnimating()
        }

        // Capture a local instance of the spinner we can use for the blocks to retain
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

        spinnerView.isHidden = false
        spinnerView.layer.removeAllAnimations()
        spinnerView.transform = .identity
        refreshSpinnerView()

        // If not animated, call these blocks right away
        if !animated {
            scalingAnimationBlock()
            crossFadeAnimationBlock()
            completionBlock(true)
            return
        }

        // Call the animation blocks
        spinnerView.transform = isLoading ? .identity.rotated(by: .pi).scaledBy(x: 0.01, y: 0.01) : .identity
        spinnerView.alpha = isLoading ? 0.0 : 1.0
        UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: [],
                       animations: scalingAnimationBlock, completion: completionBlock)
        UIView.animate(withDuration: 0.2, delay: 0.0, options: [], animations: crossFadeAnimationBlock)
    }

    /// Create a new spinner view instance based on the promo view's current state.
    ///
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
        spinnerView.color = isDarkMode ? .white : .gray

        // Update the style based on how large the promo view is
        // Only do this when we're loading (ie, we're going *into* a fetch cycle)
        // so the size doesn't randomly change as we're winding down
        if isLoading {
            let useLargeSize = frame.height > PromoView.largeSpinnerRequiredHeight
            spinnerView.style = useLargeSize ? .whiteLarge : .gray
        }
        spinnerView.sizeToFit()

        // Position the spinner in the middle of the view
        spinnerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

// MARK: - Interaction Animations

extension PromoView {

    /// If necessasry, providers can short-circuit and cancel any in-progress
    /// tap/dragging interactions if they determine their content became non-interactive in the meantime.
    /// - Parameter animated: Whether the cancel event is animated or not.
    public func cancelTapInteraction(animated: Bool = false) {
        setZoomed(false, animated: animated)
        isInteractionCancelled = true
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Disable the animation while we're showing a spinner
        if isLoading {
            canPlayTapAnimation = false
            return
        }

        // Reset the cancellation flag from the previous interaction
        isInteractionCancelled = false

        // If we're not loading, handle interaction events
        if let provider = currentProvider, let touch = touches.first {
            provider.didDragInside?(promoView: self, with: touch)
        }

        // If we have a promo visible, check its delegate to make sure we can play the anim
        if let provider = currentProvider,
            let touch = touches.first,
            !(provider.shouldPlayInteractionAnimation?(for: self, with: touch) ?? true) {
            canPlayTapAnimation = false
            return
        }

        // Start playing the zoom animation
        setZoomed(true, animated: true)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard !isInteractionCancelled, canPlayTapAnimation, let touch = touches.first else { return }
        let zoomed = bounds.contains(touch.location(in: self))
        setZoomed(zoomed, animated: true)
        if let provider = currentProvider, let touch = touches.first {
            provider.didDragInside?(promoView: self, with: touch)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        canPlayTapAnimation = true
        setZoomed(false, animated: true)
        guard !isInteractionCancelled else { return }
        if let provider = currentProvider, let touch = touches.first {
            provider.didTapUpInside?(promoView: self, with: touch)
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        canPlayTapAnimation = true
        setZoomed(false, animated: true)
    }

    private func setZoomed(_ zoomed: Bool, animated: Bool = false) {
        guard isZoomed != zoomed else { return }
        isZoomed = zoomed
        UIView.animate(withDuration: animated ? 0.45 : 0.0,
                       delay: 0.0,
                       usingSpringWithDamping: 1.0,
                       initialSpringVelocity: 1.0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.containerView.transform = zoomed ? CGAffineTransformScale(.identity, 0.985, 0.985) : .identity
        }
    }
}
