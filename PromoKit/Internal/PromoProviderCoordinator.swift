//
//  PromoProviderCoordinator.swift
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

import Foundation
import Network

/// A model object that handles querying for, and choosing
/// the highest priority provider to be displayed.
internal class PromoProviderCoordinator: PromoPathMonitorDelegate {

    /// The promo view managing this provider coordinator.
    private(set) weak var promoView: PromoView?

    /// The array of providers managed by this coordinator,
    /// in order of priority.
    public var providers: [PromoProvider]?

    /// The currently displayed provider.
    public var currentProvider: PromoProvider?

    /// A retry interval for failed provider fetches.
    public var retryInterval: TimeInterval = 30

    /// The maximum amount of time to wait for a provider fetch before treating it as a failure.
    public var fetchTimeout: TimeInterval = 15

    /// A handler that is triggered whenever a new provider is chosen.
    public var providerUpdatedHandler: ((PromoProvider?) -> Void)?

    /// A handler called if the fetch fails, and no valid provider is found.
    public var providerFetchFailedHandler: (() -> Void)?

    /// Track fetching state.
    private(set) public var isFetching = false

    // MARK: Private

    // The network connection observer
    let networkMonitor = PromoPathMonitor()

    // The provider currently being fetched
    var queryingProvider: PromoProvider?

    // The unique token for the currently active provider fetch.
    var queryingProviderToken: UUID?

    // Tracking the last known response of each provider, so we know which retry policy to apply
    let providerFetchResults = NSMapTable<AnyObject, NSNumber>(keyOptions: .weakMemory,
                                                               valueOptions: .copyIn)

    // Track the last time each provider returned a result so refresh intervals can be applied per-provider.
    let providerFetchDates = NSMapTable<AnyObject, NSDate>(keyOptions: .weakMemory,
                                                           valueOptions: .copyIn)

    // The pending timeout work item for the currently active provider fetch.
    private var fetchTimeoutWorkItem: DispatchWorkItem?

    // MARK: Init

    init(promoView: PromoView) {
        self.promoView = promoView
        networkMonitor.delegate = self
        networkMonitor.start()
    }

    deinit {
        networkMonitor.cancel()
        queryingProvider = nil
        cancelFetch()
    }

    /// Clears all provider fetch history and cancels any in-progress fetch.
    public func reset() {
        cancelFetch()
        providerFetchResults.removeAllObjects()
        providerFetchDates.removeAllObjects()
    }
}

// MARK: - Provider Access

extension PromoProviderCoordinator {
    /// Returns the first provider in the list whose concrete type matches the given class.
    /// - Parameter providerClass: The class to match against.
    /// - Returns: The matching provider, or nil if none is found.
    internal func providerForClass(_ providerClass: AnyClass) -> PromoProvider? {
        return providers?.first(where: { provider in
            type(of: provider) == providerClass
        })
    }
}

// MARK: - Provider Fetching

extension PromoProviderCoordinator {

    /// Start the process of looping through each provider,
    /// and see which one is most appropriate at the moment.
    internal func fetchBestProvider(from provider: PromoProvider? = nil) {
        guard let provider = nextValidProvider(from: provider) else {
            providerUpdatedHandler?(nil)
            return
        }

        // Set flag that we're fetching, so we can cancel out of pending blocks
        isFetching = true

        // Start fetch request on this provider
        startContentFetch(for: provider)
    }

    /// Cancels an in-progress fetch.
    /// Any late callbacks from the canceled provider are ignored.
    internal func cancelFetch() {
        isFetching = false
        invalidateActiveFetch()
    }

    /// When a potentially valid provider is found, instruct it to start loading
    /// its content (whether that is on disk, or via network) and return whether
    /// any valid content was found or not.
    /// - Parameter provider: The provider to be instructed to load its content.
    private func startContentFetch(for provider: PromoProvider) {
        guard isFetching else { return }

        // Check if we need to skip this one as its time interval hasn't elapsed yet
        if skipToNextProvider(provider) { return }

        // Assign the promo view to this provider if it requires it
        if let promoView { provider.didMoveToPromoView?(promoView) }

        // Store a class reference to this provider
        invalidateFetchTimeout()
        let queryingProviderToken = UUID()
        self.queryingProvider = provider
        self.queryingProviderToken = queryingProviderToken

        // Capture a copy of this provider we can use to compare to the class one in the completion handler
        let queryingProvider: PromoProvider = provider

        scheduleFetchTimeout(for: queryingProvider, token: queryingProviderToken)

        // Define the closure, and use address-comparison to ensure it's still valid at completion
        let handler: ((PromoProviderFetchContentResult) -> Void) = { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard self?.isActiveFetch(for: queryingProvider, token: queryingProviderToken) ?? false else { return }
                self?.didReceiveResult(result, from: queryingProvider)
            }
        }

        // Start the fetch request on the new provider.
        // Defer to the next run loop, so we don't end up overloading the call stack if all of these providers
        // execute on the main run loop.
        DispatchQueue.main.async { [weak self] in
            guard self?.isActiveFetch(for: queryingProvider, token: queryingProviderToken) ?? false,
                  let promoView = self?.promoView else { return }
            queryingProvider.fetchNewContent(for: promoView, with: handler)
        }
    }

    /// Callback method invoked by a provider after it has finished attempting fetching its content and
    /// is ready to return the results of its fetch.
    /// - Parameters:
    ///   - result: The result of the content fetch reported by the provider
    ///   - provider: The provider performing the request
    private func didReceiveResult(_ result: PromoProviderFetchContentResult, from provider: PromoProvider) {
        invalidateActiveFetch()

        // Save the result to our map table so we can consider it for future fetches
        providerFetchResults.setObject(result.rawValue as NSNumber, forKey: provider)
        providerFetchDates.setObject(Date() as NSDate, forKey: provider)

        // If this provider reported it has valid content, lets make it the current provider and stop here
        if result == .contentAvailable {
            currentProvider = provider
            providerUpdatedHandler?(provider)
            cancelFetch()
            return
        }

        // Otherwise, move to the next provider and keep looking
        guard isFetching, let nextProvider = nextValidProvider(after: provider) else {
            cancelFetch()
            providerFetchFailedHandler?()
            return
        }

        // Perform next fetch
        startContentFetch(for: nextProvider)
    }

    /// Find the next valid provider, either from the start, from a previously tested provider,
    /// or from the next one in line.
    /// - Parameters:
    ///   - fromProvider: A provider to start testing from. If nil, the first provider is used.
    ///   - afterProvider: Alternatively, skipping this provider, the next valid provider after this one.
    /// - Returns: The next provider that should be tested for new content.
    private func nextValidProvider(from fromProvider: PromoProvider? = nil,
                                   after afterProvider: PromoProvider? = nil) -> PromoProvider? {
        guard let providers = self.providers, !providers.isEmpty else { return nil }

        // Fetch the index after the given provider, or start at the beginning otherwise
        let provider = afterProvider ?? fromProvider ?? nil
        var startIndex = (provider != nil) ? (providers.firstIndex { $0 === provider } ?? 0) : 0
        if afterProvider != nil { startIndex += 1 }

        // If the network is up, start with whatever first provider we have. If not, find the first not needing internet
        for nextProvider in providers.dropFirst(startIndex) {
            // Providers that don't need internet are always valid
            if !(nextProvider.isInternetAccessRequired ?? false) { return nextProvider }

            // If the provider requires internet, we'll use it if the internet is available,
            // or if the provider declares it can save its content offline.
            if networkMonitor.hasInternetAccess || (nextProvider.isOfflineCacheAvailable ?? false) {
                return nextProvider
            }
        }

        return nil
    }

    /// Checks if the provider should be skipped because it isn't eligible to be fetched again yet
    /// - Parameter provider: The provider to check
    /// - Returns: A boolean on whether this provider should be skipped or not
    private func skipToNextProvider(_ provider: PromoProvider) -> Bool {
        guard let previousFetchDate = providerFetchDates.object(forKey: provider),
              let value = providerFetchResults.object(forKey: provider) else { return false }
        let result = PromoProviderFetchContentResult(rawValue: value.intValue)

        var timeInterval: TimeInterval = 0
        switch result {
        case .fetchRequestFailed:
            timeInterval = retryInterval
        case .noContentAvailable, .contentAvailable:
            timeInterval = provider.fetchRefreshInterval ?? 0
        case .none:
            timeInterval = 0
        }

        guard timeInterval > 0 else { return false }

        // If we're not past the time-out interval yet, skip to the next provider
        let elapsedTime = Date().timeIntervalSince(previousFetchDate as Date)
        guard elapsedTime < timeInterval else { return false }

        if let nextProvider = nextValidProvider(after: provider) {
            DispatchQueue.main.async { [weak self] in
                guard self?.isFetching ?? false else { return }
                self?.startContentFetch(for: nextProvider)
            }
        } else {
            cancelFetch()
        }
        return true
    }

    /// Returns true only if the given provider and token match the currently active fetch,
    /// allowing stale callbacks from cancelled or timed-out fetches to be discarded.
    private func isActiveFetch(for provider: PromoProvider, token: UUID) -> Bool {
        guard let currentQueryingProvider = queryingProvider,
              let currentQueryingProviderToken = queryingProviderToken else { return false }
        return currentQueryingProvider === provider && currentQueryingProviderToken == token
    }

    /// Clears the active fetch state so any in-flight callbacks are treated as stale.
    private func invalidateActiveFetch() {
        queryingProvider = nil
        queryingProviderToken = nil
        invalidateFetchTimeout()
    }

    /// Cancels any pending fetch timeout work item.
    private func invalidateFetchTimeout() {
        fetchTimeoutWorkItem?.cancel()
        fetchTimeoutWorkItem = nil
    }

    /// Schedules a timeout that will treat the current fetch as failed if it doesn't
    /// complete within `fetchTimeout` seconds.
    /// - Parameters:
    ///   - provider: The provider currently being fetched.
    ///   - token: The unique token for this fetch, used to discard the timeout if the fetch completes first.
    private func scheduleFetchTimeout(for provider: PromoProvider, token: UUID) {
        guard fetchTimeout > 0 else { return }

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard self?.isActiveFetch(for: provider, token: token) ?? false else { return }
            self?.didReceiveResult(.fetchRequestFailed, from: provider)
        }
        fetchTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + fetchTimeout, execute: timeoutWorkItem)
    }
}

// MARK: - PromoPathMonitorDelegate

extension PromoProviderCoordinator {

    /// Called when network connectivity changes. If we're currently showing an offline provider
    /// and the internet returns, triggers a fresh fetch to promote an online provider if one is available.
    func pathMonitor(_ pathMonitor: PromoPathMonitor, didUpdateToPath path: NWPath?) {
        guard let path, let provider = currentProvider else { return }

        // If we're already showing an internet enabled provider, we can skip, assuming it may still render offline.
        let internetConnected = path.status == .satisfied
        if internetConnected, (provider.isInternetAccessRequired ?? false) { return }

        // We're apparently showing an offline provider, let's take this as a chance to see if any new internet content has arrived.
        fetchBestProvider()
    }
}
