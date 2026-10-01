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

/// Fetches eligible providers in priority order and selects the first with content.
internal class PromoProviderCoordinator: PromoPathMonitorDelegate {

    /// The promo view managing this provider coordinator.
    private(set) weak var promoView: PromoView?

    /// The array of providers managed by this coordinator,
    /// in order of priority.
    public var providers: [PromoProvider]?

    /// The selected provider, retained while a size refresh replaces its displayed content.
    public var currentProvider: PromoProvider?

    /// A retry interval for failed provider fetches.
    public var retryInterval: TimeInterval = 30

    /// The maximum amount of time to wait for a provider fetch before treating it as a failure.
    public var fetchTimeout: TimeInterval = 15

    /// Reports a selected provider, or `nil` when no providers are eligible.
    public var providerUpdatedHandler: ((PromoProvider?) -> Void)?

    /// Reports that attempted fetches produced no replacement content.
    public var providerFetchFailedHandler: (() -> Void)?

    /// Track fetching state.
    private(set) public var isFetching = false

    /// Identifies the reload, including work between individual provider requests.
    private(set) var fetchGeneration = UUID()

    // MARK: - Private

    // The network connection observer (injected for tests; defaults to a real path monitor)
    let networkMonitor: PromoPathMonitoring

    // The provider currently being fetched
    var queryingProvider: PromoProvider?

    // The unique token for the currently active provider fetch.
    var queryingProviderToken: UUID?

    // The last result determines whether the refresh or retry interval applies.
    let providerFetchResults = NSMapTable<AnyObject, NSNumber>(keyOptions: .weakMemory,
                                                               valueOptions: .copyIn)

    // Completion dates used to enforce each provider's interval.
    let providerFetchDates = NSMapTable<AnyObject, NSDate>(keyOptions: .weakMemory,
                                                           valueOptions: .copyIn)

    // The pending timeout work item for the currently active provider fetch.
    private var fetchTimeoutWorkItem: DispatchWorkItem?

    // Run only when a reload reaches a provider that will actually be fetched.
    private var beforeFetch: (() -> Void)?
    private var hasRequestedFetch = false
    private var hasAttemptedFetch = false
    private var needsConnectivityRecheck = false

    // MARK: - Init

    init(promoView: PromoView, networkMonitor: PromoPathMonitoring = PromoPathMonitor()) {
        self.promoView = promoView
        self.networkMonitor = networkMonitor
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

    /// Starts a new resolution from the given provider, or the highest-priority provider.
    /// Calls `beforeFetch` only when a provider passes the refresh and retry interval checks.
    internal func fetchBestProvider(from startingProvider: PromoProvider? = nil,
                                    beforeFetch: (() -> Void)? = nil) {
        cancelFetch()
        hasRequestedFetch = true
        self.beforeFetch = beforeFetch
        guard let provider = nextValidProvider(from: startingProvider) else {
            // Removing content also clears its cooldown so a reconnect can restore it.
            if let currentProvider {
                providerFetchResults.removeObject(forKey: currentProvider)
                providerFetchDates.removeObject(forKey: currentProvider)
            }
            currentProvider = nil
            providerUpdatedHandler?(nil)
            return
        }

        // Pending work checks this flag before continuing.
        isFetching = true

        // Start fetch request on this provider
        startContentFetch(for: provider)
    }

    /// Cancels coordinator resolution and ignores late callbacks.
    /// The provider's underlying work may continue.
    internal func cancelFetch() {
        isFetching = false
        hasAttemptedFetch = false
        needsConnectivityRecheck = false
        beforeFetch = nil
        fetchGeneration = UUID()
        invalidateActiveFetch()
    }

    /// Starts the provider's fetch unless its refresh or retry interval requires skipping it.
    private func startContentFetch(for provider: PromoProvider) {
        guard isFetching else { return }
        let generation = fetchGeneration

        if skipToNextProvider(provider) { return }
        guard isFetching, fetchGeneration == generation else { return }

        let preparation = beforeFetch
        beforeFetch = nil
        preparation?()
        guard isFetching, fetchGeneration == generation else { return }

        // Let the provider record its host before fetching.
        if let promoView { provider.didMoveToPromoView?(promoView) }
        // Both hooks can synchronously replace providers or cancel this reload.
        guard isFetching, fetchGeneration == generation else { return }

        // Track this attempt independently of earlier requests to the same provider.
        hasAttemptedFetch = true
        invalidateFetchTimeout()
        let queryingProviderToken = UUID()
        self.queryingProvider = provider
        self.queryingProviderToken = queryingProviderToken

        // Capture the provider identity for later callback validation.
        let queryingProvider: PromoProvider = provider

        scheduleFetchTimeout(for: queryingProvider, token: queryingProviderToken)

        // Process only the active request's results, always on the main queue.
        let handler: ((PromoProviderFetchContentResult) -> Void) = { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard self?.isActiveFetch(for: queryingProvider, token: queryingProviderToken) ?? false else { return }
                self?.didReceiveResult(result, from: queryingProvider)
            }
        }

        // If the provider needs a loading indicator, show it now before the fetch starts.
        let showsLoadingIndicator = provider.showsLoadingIndicatorDuringFetch ?? false
        guard isActiveFetch(for: queryingProvider, token: queryingProviderToken) else { return }
        if showsLoadingIndicator {
            promoView?.setIsLoading(true, animated: true)
        }

        // Defer to avoid recursive fetch chains when providers complete synchronously.
        DispatchQueue.main.async { [weak self] in
            guard self?.isActiveFetch(for: queryingProvider, token: queryingProviderToken) ?? false,
                  let promoView = self?.promoView else { return }
            queryingProvider.fetchNewContent(for: promoView, with: handler)
        }
    }

    /// Records a fetch result and either selects the provider or continues resolution.
    /// - Parameters:
    ///   - result: The result of the content fetch reported by the provider
    ///   - provider: The provider performing the request
    private func didReceiveResult(_ result: PromoProviderFetchContentResult, from provider: PromoProvider) {
        invalidateActiveFetch()

        // Record completion for future refresh and retry checks.
        providerFetchResults.setObject(result.rawValue as NSNumber, forKey: provider)
        providerFetchDates.setObject(Date() as NSDate, forKey: provider)

        // Stop at the first provider with content.
        if result == .contentAvailable {
            currentProvider = provider
            finishFetch { providerUpdatedHandler?(provider) }
            return
        }

        // Otherwise, move to the next provider and keep looking
        guard isFetching, let nextProvider = nextValidProvider(after: provider) else {
            finishFetch { providerFetchFailedHandler?() }
            return
        }

        // Perform next fetch
        startContentFetch(for: nextProvider)
    }

    /// Finish the current request before handling a connectivity transition that
    /// arrived during it. A host-triggered reload or cancellation takes priority.
    private func finishFetch(notify: () -> Void) {
        let shouldRecheckConnectivity = needsConnectivityRecheck
        cancelFetch()
        let completedGeneration = fetchGeneration
        notify()
        guard shouldRecheckConnectivity, fetchGeneration == completedGeneration else { return }
        pathMonitor(networkMonitor, didUpdateConnectivity: networkMonitor.hasInternetAccess)
    }

    /// Finds the next provider eligible under the current network conditions.
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

        // Preserve priority order while filtering by network and cache availability.
        for nextProvider in providers.dropFirst(startIndex) {
            // Providers that don't need internet are always valid
            if !(nextProvider.isInternetAccessRequired ?? false) { return nextProvider }

            // Internet-dependent providers may still serve cached content offline.
            if networkMonitor.hasInternetAccess || (nextProvider.isOfflineCacheAvailable ?? false) {
                return nextProvider
            }
        }

        return nil
    }

    /// Advances past a provider whose refresh or retry interval has not elapsed.
    /// Returns `true` when the provider is skipped, including when that ends resolution.
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

        // Skip this provider while its refresh or retry interval is active.
        let elapsedTime = Date().timeIntervalSince(previousFetchDate as Date)
        guard elapsedTime < timeInterval else { return false }

        if let nextProvider = nextValidProvider(after: provider) {
            let generation = fetchGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isFetching,
                      self.fetchGeneration == generation else { return }
                self.startContentFetch(for: nextProvider)
            }
        } else {
            let didAttemptFetch = hasAttemptedFetch
            // A failed request followed by a throttled tail still ends the load.
            // If every provider was throttled, keep the existing content as-is.
            finishFetch {
                if didAttemptFetch { providerFetchFailedHandler?() }
            }
        }

        return true
    }

    /// Returns true only if the given provider and token match the currently active fetch,
    /// allowing stale callbacks from cancelled or timed-out fetches to be discarded.
    private func isActiveFetch(for provider: PromoProvider, token: UUID) -> Bool {
        guard isFetching,
              let currentQueryingProvider = queryingProvider,
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

    /// Rechecks provider eligibility after connectivity changes, deferring until any active fetch finishes.
    func pathMonitor(_ pathMonitor: PromoPathMonitoring, didUpdateConnectivity connected: Bool) {
        guard !isFetching else {
            needsConnectivityRecheck = true
            return
        }
        guard let provider = currentProvider else {
            if connected && hasRequestedFetch { fetchBestProvider() }
            return
        }

        // An already-selected online provider needs no promotion when connectivity returns.
        if connected, (provider.isInternetAccessRequired ?? false) { return }

        // Resolve a fallback when offline, or a higher-priority provider when back online.
        fetchBestProvider()
    }
}
