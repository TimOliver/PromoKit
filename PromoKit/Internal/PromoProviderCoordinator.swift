//
//  PromoProviderCoordinator.swift
//
//  Copyright 2024 Timothy Oliver. All rights reserved.
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

/// A class that handles querying for, and choosing
/// the provider that should be currently displayed.
internal class PromoProviderCoordinator: PromoPathMonitorDelegate {

    /// The promo view managing this provider coordinator
    private(set) var promoView: PromoView?

    /// The array of providers managed by this coordinator,
    /// in order of priority
    public var providers: [PromoProvider]?

    /// The currently displayed provider
    public var currentProvider: PromoProvider?

    /// A retry interval for failed provider fetches
    public var retryInterval: TimeInterval = 30

    /// A handler that is triggered whenever a new provider is chosen
    public var providerUpdatedHandler: ((PromoProvider?) -> Void)?

    /// A handler called if the fetch fails, and no valid provider is found
    public var providerFetchFailedHandler: (() -> Void)?

    /// Track fetching state
    private(set) public var isFetching = false

    // MARK: Private

    // The network connection observer
    let networkMonitor = PromoPathMonitor()

    // The provider currently being fetched
    var queryingProvider: PromoProvider?

    // Tracking the last known response of each provider, so we know what retry policy to apply
    let providerFetchResults = NSMapTable<AnyObject, NSNumber>(keyOptions: .weakMemory, valueOptions: .copyIn)

    // Track the last time a fetch attempt was made so we can defer any new fetches until the retry intervals have passed.
    var previousFetchTime: Date?

    // MARK: - Class Creation
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

    // Reset all of the state, including all timers
    public func reset() {
        cancelFetch()
        providerFetchResults.removeAllObjects()
        previousFetchTime = nil
    }
}

// MARK: - Provider Access

extension PromoProviderCoordinator {
    internal func providerForClass(_ providerClass: AnyClass) -> PromoProvider? {
        return providers?.first(where: { provider in
            type(of: provider) == providerClass
        })
    }
}

// MARK: - Provider Fetching

extension PromoProviderCoordinator {
    /// Start the process of looping through each provider, and see which one is most appropriate right now
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
    /// It's possible the cancel request can happen right after a web request has been made.
    /// In this case, that fetch is allowed to continue, and that provider may become the current one, but
    /// subsequent fetches are then canceled. This is to ensure we don't cancel partial requests without confirming the next time interval.
    internal func cancelFetch() {
        previousFetchTime = Date()
        isFetching = false
    }

    private func startContentFetch(for provider: PromoProvider) {
        guard isFetching else { return }

        // Check if we need to skip this one as its time interval hasn't elapsed yet
        if skipToNextProvider(provider) { return }

        // Assign the promo view to this provider if it requires it
        if let promoView { provider.didMoveToPromoView?(promoView) }

        // Store a class reference to this provider
        self.queryingProvider = provider

        // Capture a copy of this provider we can use to compare to the class one in the completion handler
        let queryingProvider: PromoProvider = provider

        // Define the closure, and use address-comparison to ensure it's still valid at completion
        let handler: ((PromoProviderFetchContentResult) -> Void) = { [weak self] result in
            // Check the current querying provider against the one we captured when we started
            // the closure and make sure they match.
            guard let currentQueryingProvider = self?.queryingProvider,
                  currentQueryingProvider === queryingProvider else { return }
            DispatchQueue.main.async { [weak self] in
                self?.didReceiveResult(result, from: queryingProvider)
            }
        }

        // Start the fetch request on the new provider.
        // Defer to the next run loop, so we don't end up overloading the call stack if all of these providers
        // execute on the main run loop.
        DispatchQueue.main.async { [weak self] in
            guard (self?.isFetching ?? false), let promoView = self?.promoView else { return }
            queryingProvider.fetchNewContent(for: promoView, with: handler)
        }
    }

    private func didReceiveResult(_ result: PromoProviderFetchContentResult, from provider: PromoProvider) {
        // Save the result to our map table so we can consider it for future fetches
        providerFetchResults.setObject(result.rawValue as NSNumber, forKey: provider)

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

    /// Find the next valid provider, either from the start, from a provided provider, or from the next one in line
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
    private func skipToNextProvider(_ provider: PromoProvider) -> Bool {
        guard (provider.isInternetAccessRequired ?? false),
              let previousFetchTime,
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

        // If we're not past the time-out interval yet, skip to the next provider
        if previousFetchTime.timeIntervalSinceNow < timeInterval,
           let nextProvider = nextValidProvider(after: provider) {
            DispatchQueue.main.async { [weak self] in
                guard self?.isFetching ?? false else { return }
                self?.startContentFetch(for: nextProvider)
            }
        }
        return true
    }
}

// MARK: - Network Path

extension PromoProviderCoordinator {

    func pathMonitor(_ pathMonitor: PromoPathMonitor, didUpdateToPath path: NWPath?) {
        guard let path, let provider = currentProvider else { return }

        // If we're already showing an internet enabled provider, we can skip, assuming it may still render offline.
        let internetConnected = path.status == .satisfied
        if internetConnected, (provider.isInternetAccessRequired ?? false) { return }

        // We're apparently showing an offline provider, let's take this as a chance to see if any new internet content has arrived.
        fetchBestProvider()
    }
}
