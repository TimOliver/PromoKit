//
//  PromoProviderCoordinator.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 19/3/2024.
//

import Foundation
import Network
import os.lock

// A shared dispatch queue for receiving network update events
let networkPathQueue = DispatchQueue(label: "dev.tim.promokit.network", qos: .utility)

/// A class that handles querying for, and choosing
/// the provider that should be currently displayed.
internal class PromoProviderCoordinator {

    /// The array of providers managed by this coordinator,
    /// in order of priority
    public var providers: [PromoProvider]?

    /// The currently displayed provider
    public var currentProvider: PromoProvider?

    /// A retry interval for failed provider fetches
    public var retryInterval: TimeInterval = 30

    /// A handler that is triggered whenever a new provider is chosen
    public var providerUpdatedHandler: ((PromoProvider?) -> Void)?

    /// Track fetching state
    private(set) public var isFetching = false
    
    // MARK: Private

    // Tracking when we come online and offline
    let pathMonitor = NWPathMonitor()

    // The last captured path value from the path monitor
    var lastPath: NWPath?

    // The provider currently being fetched
    var queryingProvider: PromoProvider?

    // Tracking the last known response of each provider, so we know what retry policy to apply
    let providerFetchResults = NSMapTable<AnyObject, NSNumber>(keyOptions: .weakMemory, valueOptions: .copyIn)

    // Track the last time a fetch attempt was made so we can defer any new fetches until the retry intervals have passed.
    var previousFetchTime: Date? = nil

    // Thread-safe lock for mutating the internet access flag
    let unfairLock: UnsafeMutablePointer<os_unfair_lock> = {
        let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
        return pointer
    }()

    // MARK: - Class Creation

    init() {
        // Start listening for network updates
        pathMonitor.start(queue: networkPathQueue)
        pathMonitor.pathUpdateHandler = { [weak self] newPath in
            self?.pathDidUpdate(to: newPath)
        }
    }

    deinit {
        queryingProvider = nil
        cancelFetch()
        pathMonitor.cancel()

        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    // Reset all of the state, including all timers
    public func reset() {
        cancelFetch()
        providerFetchResults.removeAllObjects()
        previousFetchTime = nil
    }
}

// MARK: - Provider Fetching

extension PromoProviderCoordinator {
    /// Start the process of looping through each provider, and see which one is most appropriate right now
    internal func fetchBestProvider() {
        guard let provider = nextValidProvider() else {
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
            guard (self?.isFetching ?? false) else { return }
            queryingProvider.fetchNewContent(with: handler)
        }
    }

    private func didReceiveResult(_ result: PromoProviderFetchContentResult, from provider: PromoProvider) {
        // Save the result to our map table so we can consider it for future fetches
        providerFetchResults.setObject(NSNumber(integerLiteral: result.rawValue), forKey: provider)

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
            return
        }

        // Perform next fetch
        startContentFetch(for: nextProvider)
    }

    /// Find the next valid provider in the list, following on after the provided one
    private func nextValidProvider(after provider: PromoProvider? = nil) -> PromoProvider? {
        guard let providers = self.providers, !providers.isEmpty else { return nil }
        // Fetch the index after the given provider, or start at the beginning otherwise
        let startIndex = (provider != nil) ? (providers.firstIndex{ $0 === provider } ?? 0) + 1 : 0

        // If the network is up, start with whatever first provider we have. If not, find the first not needing internet
        for nextProvider in providers.dropFirst(startIndex) {
            if hasInternetAccess || (!hasInternetAccess && !(nextProvider.isInternetAccessRequired ?? false)) {
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
                guard (self?.isFetching ?? false) else { return }
                self?.startContentFetch(for: nextProvider)
            }
        }
        return true
    }
}

// MARK: - Network Path

extension PromoProviderCoordinator {

    private var hasInternetAccess: Bool {
        // In case it's being mutated on another thread,
        // use a lock to fetch the current path status
        // and check if we're online.
        var value = false
        os_unfair_lock_lock(unfairLock)
        if let lastPath {
            value = lastPath.status == .satisfied
        }
        os_unfair_lock_unlock(unfairLock)
        return value
    }

    private func pathDidUpdate(to path: NWPath) {
        // Since NWPathMonitor constantly sends updates,
        // we'll use our background thread to detect and discard
        // events that don't actually change the status.
        var statusDidChange = false
        os_unfair_lock_lock(unfairLock)
        if let lastPath {
            statusDidChange = lastPath.status != path.status
        }
        lastPath = path
        os_unfair_lock_unlock(unfairLock)
        if !statusDidChange { return }

        // If we were showing offline content, and the internet came back up,
        // perform a new fetch to see if there's an online provider we should show
        DispatchQueue.main.async { [weak self] in
            self?.performNewFetchIfNeeded(with: path)
        }
    }

    private func performNewFetchIfNeeded(with path: NWPath) {
        guard let provider = currentProvider else { return }

        // If we're already showing an internet enabled provider, we can skip, assuming it may still render offline.
        let internetConnected = path.status == .satisfied
        if internetConnected, (provider.isInternetAccessRequired ?? false) { return }

        // We're apparently showing an offline provider, let's take this as a chance to see if any new internet content has arrived.
        fetchBestProvider()
    }
}
