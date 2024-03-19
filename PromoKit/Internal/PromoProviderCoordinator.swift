//
//  PromoProviderCoordinator.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 19/3/2024.
//

import Foundation
import Network

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

    /// A handler that is triggered whenever a new provider is chosen
    public var providerUpdatedHandler: ((PromoProvider?) -> Void)?

    // MARK: Private

    // Tracking when we come online and offline
    let pathMonitor = NWPathMonitor()

    // The provider currently being fetched
    public var queryingProvider: PromoProvider?

    // MARK: - Class Creation

    init() {
        // Start listening for network updates
        pathMonitor.start(queue: networkPathQueue)
        pathMonitor.pathUpdateHandler = { [weak self] newPath in
            self?.pathDidUpdate(to: newPath)
        }
    }

    deinit {
        cancelFetch()
        pathMonitor.cancel()
    }

}

// MARK: - Provider Fetching

extension PromoProviderCoordinator {
    // Start the process of looping through each provider, and see which one is most appropriate right now
    internal func fetchBestProvider() {
        guard let provider = nextValidProvider() else {
            providerUpdatedHandler?(nil)
            return
        }

        // Create an object to track this query and start fetching
        queryingProvider = provider
        startContentFetch(for: provider)
    }

    // Cancel an in-progress fetch
    internal func cancelFetch() {
        queryingProvider = nil
    }

    private func startContentFetch(for provider: PromoProvider) {
        // Capture a copy of this provider we can use to compare to the class one
        let queryingProvider: PromoProvider = provider

        // Define the closure, and use address-comparison to ensure it's still valid at completion
        let handler: ((PromoProviderFetchContentResult) -> Void) = { [weak self] result in
            // Check the current querying provider against the one we captured when we started
            // the closure and make sure they match.
            guard let currentQueryingProvider = self?.queryingProvider,
                  currentQueryingProvider === queryingProvider else { return }
            self?.didReceiveResult(result, from: queryingProvider)
        }

        // Forward the handler to the provider
        queryingProvider.fetchNewContent(with: handler)
    }

    private func didReceiveResult(_ result: PromoProviderFetchContentResult, from provider: PromoProvider) {
        // If this provider returned it has valid content, lets make it the current provider and stop here
        if result == .contentAvailable {
            currentProvider = provider
            providerUpdatedHandler?(provider)
            cancelFetch()
            return
        }

        // Otherwise, move to the next provider and keep looking
        guard let nextProvider = nextValidProvider(after: provider) else {
            providerUpdatedHandler?(nil)
            cancelFetch()
            return
        }

        queryingProvider = nextProvider
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
}

// MARK: - Network Path

extension PromoProviderCoordinator {

    private var hasInternetAccess: Bool {
        pathMonitor.currentPath.status == .satisfied
    }

    private func pathDidUpdate(to path: NWPath) {
        // If we were showing offline content, and the internet came back up,
        // perform a new fetch to see if there's an online provider we should show
    }
}
