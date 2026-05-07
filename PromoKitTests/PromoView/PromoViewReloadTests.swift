import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoViewReloadTests: XCTestCase {

    func testManualReloadResolvesProviderBeforeDisplay() {
        let provider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate
        promoView.reloadsAutomatically = false
        promoView.providers = [provider]

        // No superview, no auto-reload — the host explicitly drives the reload to inspect the result.
        promoView.reload()

        wait(for: [delegate.resolveExpectation, delegate.updateExpectation], timeout: 1.0, enforceOrder: true)
        XCTAssertNil(promoView.superview)
        XCTAssertTrue(delegate.resolvedProvider === provider)
        XCTAssertTrue(delegate.updatedProvider === provider)
    }

    func testManualReloadFailsToResolveWhenNoContentAvailable() {
        let provider = TestPromoProvider(result: .noContentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate
        promoView.reloadsAutomatically = false
        promoView.providers = [provider]

        promoView.reload()

        wait(for: [delegate.resolveFailedExpectation], timeout: 1.0)
        XCTAssertNil(promoView.currentProvider)
    }

    func testAssigningProvidersDoesNotReloadWhenAutomaticReloadingDisabled() {
        let provider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promoView.reloadsAutomatically = false

        promoView.providers = [provider]

        // Give any stray async fetch dispatch a chance to run before asserting.
        let settle = expectation(description: "Run loop spins without triggering a reload")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertNil(promoView.currentProvider)
    }

    func testReloadIfNeededIsNoOpWhileFetching() {
        let neverCompletingProvider = TestPromoProvider(result: .contentAvailable, completes: false)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        let fetchStarted = expectation(description: "Initial fetch begins")
        neverCompletingProvider.onFetch = { fetchStarted.fulfill() }
        promoView.providers = [neverCompletingProvider]
        wait(for: [fetchStarted], timeout: 1.0)
        XCTAssertEqual(neverCompletingProvider.fetchCount, 1)

        // While the fetch is in flight, reloadIfNeeded must not restart the pipeline.
        promoView.reloadIfNeeded()

        let settle = expectation(description: "Run loop spins")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
        XCTAssertEqual(neverCompletingProvider.fetchCount, 1)
    }

    func testReloadContentViewReusesQueuedContentViews() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = ReuseTrackingPromoProvider()

        promoView.currentProvider = provider
        promoView.reloadContentView()
        promoView.reloadContentView()

        XCTAssertEqual(provider.contentViewIdentifiers.count, 2)
        XCTAssertEqual(provider.contentViewIdentifiers[0], provider.contentViewIdentifiers[1])
    }
}
