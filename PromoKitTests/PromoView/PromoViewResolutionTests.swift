import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoViewResolutionTests: XCTestCase {

    func testPromoViewStartsLoadingAfterBeingAttached() {
        let provider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80), providers: [provider])
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        hostView.addSubview(promoView)

        // Wait for the resolution to actually settle, not just for the fetch to begin —
        // currentProvider is only assigned after the result handler runs.
        wait(for: [delegate.resolveExpectation], timeout: 1.0)
        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertTrue(promoView.currentProvider === provider)
    }

    func testFallbackResolutionPicksSecondProviderWhenFirstHasNoContent() {
        let firstProvider = TestPromoProvider(result: .noContentAvailable)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        promoView.providers = [firstProvider, fallbackProvider]

        wait(for: [delegate.resolveExpectation, delegate.updateExpectation], timeout: 1.0, enforceOrder: true)
        XCTAssertTrue(delegate.resolvedProvider === fallbackProvider)
        XCTAssertTrue(delegate.updatedProvider === fallbackProvider)
        XCTAssertEqual(delegate.resolveCount, 1)
        XCTAssertEqual(delegate.resolveFailedCount, 0)
        XCTAssertEqual(delegate.fetchFailedCount, 0)
        XCTAssertEqual(firstProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 1)
    }

    func testFallbackResolutionPicksLaterProviderInMixedFailureChain() {
        let providers = [
            TestPromoProvider(result: .noContentAvailable),
            TestPromoProvider(result: .fetchRequestFailed),
            TestPromoProvider(result: .contentAvailable)
        ]
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        promoView.providers = providers

        wait(for: [delegate.resolveExpectation], timeout: 1.0)
        XCTAssertTrue(delegate.resolvedProvider === providers[2])
        XCTAssertEqual(delegate.resolveCount, 1)
        XCTAssertEqual(delegate.resolveFailedCount, 0)
        XCTAssertEqual(delegate.fetchFailedCount, 0)
        XCTAssertEqual(providers[0].fetchCount, 1)
        XCTAssertEqual(providers[1].fetchCount, 1)
        XCTAssertEqual(providers[2].fetchCount, 1)
    }

    func testExhaustedChainFiresFailureCallbacksExactlyOnceInOrder() {
        let providers = [
            TestPromoProvider(result: .noContentAvailable),
            TestPromoProvider(result: .noContentAvailable)
        ]
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        promoView.providers = providers

        // The resolve-failure callback fires before the older fetch-failure callback so hosts
        // listening on either contract see the same outcome.
        wait(for: [delegate.resolveFailedExpectation, delegate.fetchFailedExpectation],
             timeout: 1.0, enforceOrder: true)

        // Let any further async work settle so we can assert the callbacks didn't double-fire.
        let settle = expectation(description: "Run loop spins after exhaustion")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)

        XCTAssertEqual(delegate.resolveCount, 0)
        XCTAssertEqual(delegate.resolveFailedCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 1)
        XCTAssertNil(promoView.currentProvider)
    }

    func testEmptyProvidersListFiresBothFailureCallbacks() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        promoView.providers = []

        wait(for: [delegate.resolveFailedExpectation, delegate.fetchFailedExpectation],
             timeout: 1.0, enforceOrder: true)
        XCTAssertEqual(delegate.resolveCount, 0)
        XCTAssertEqual(delegate.resolveFailedCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 1)
        XCTAssertNil(promoView.currentProvider)
    }

    func testEmptyProviderListReportsFetchFailure() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate
        hostView.addSubview(promoView)

        promoView.providers = []

        wait(for: [delegate.fetchFailedExpectation], timeout: 1.0)
        XCTAssertNil(promoView.currentProvider)
    }

    func testReloadAfterSuccessFiresResolveAgainForReplacementProvider() {
        let firstProvider = TestPromoProvider(result: .contentAvailable)
        let secondProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        let firstResolved = expectation(description: "First provider resolves")
        let secondResolved = expectation(description: "Second provider resolves")
        delegate.onResolve = { provider in
            if provider === firstProvider { firstResolved.fulfill() }
            if provider === secondProvider { secondResolved.fulfill() }
        }

        promoView.providers = [firstProvider]
        wait(for: [firstResolved], timeout: 1.0)
        XCTAssertTrue(promoView.currentProvider === firstProvider)

        promoView.providers = [secondProvider]
        wait(for: [secondResolved], timeout: 1.0)

        XCTAssertEqual(delegate.resolveCount, 2)
        XCTAssertEqual(delegate.resolveFailedCount, 0)
        XCTAssertEqual(delegate.fetchFailedCount, 0)
        XCTAssertTrue(promoView.currentProvider === secondProvider)
    }

    func testReloadAfterSuccessFiresFailureWhenReplacementHasNoContent() {
        let firstProvider = TestPromoProvider(result: .contentAvailable)
        let failingProvider = TestPromoProvider(result: .noContentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        let firstResolved = expectation(description: "First provider resolves")
        delegate.onResolve = { provider in
            if provider === firstProvider { firstResolved.fulfill() }
        }
        promoView.providers = [firstProvider]
        wait(for: [firstResolved], timeout: 1.0)

        let failureFired = expectation(description: "Replacement triggers resolve failure")
        delegate.onResolveFailure = { failureFired.fulfill() }
        promoView.providers = [failingProvider]
        wait(for: [failureFired], timeout: 1.0)

        XCTAssertEqual(delegate.resolveCount, 1)
        XCTAssertEqual(delegate.resolveFailedCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 1)
        // Replacement providers list dropped firstProvider, so it was cleared synchronously
        // when the providers setter ran. The failed reload then leaves currentProvider nil.
        XCTAssertNil(promoView.currentProvider)
    }

    func testStaleResolutionFromCancelledReloadIsNotReported() {
        let slowProvider = TestPromoProvider(result: .contentAvailable, completionDelay: 0.3)
        let fastProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        // Wait for the slow provider's fetch to actually start so its delayed completion
        // is genuinely in flight when the second reload cancels it.
        let slowFetchStarted = expectation(description: "Slow provider begins fetching")
        slowProvider.onFetch = { slowFetchStarted.fulfill() }
        promoView.providers = [slowProvider]
        wait(for: [slowFetchStarted], timeout: 1.0)

        promoView.providers = [fastProvider]

        wait(for: [delegate.resolveExpectation], timeout: 1.0)
        XCTAssertTrue(delegate.resolvedProvider === fastProvider)

        // Give the slow provider's late callback time to attempt to land. It must be ignored
        // — neither resolve nor failure should fire a second time.
        let stale = expectation(description: "Slow provider's cancelled callback gets a chance")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { stale.fulfill() }
        wait(for: [stale], timeout: 1.0)

        XCTAssertEqual(delegate.resolveCount, 1)
        XCTAssertEqual(delegate.resolveFailedCount, 0)
        XCTAssertEqual(delegate.fetchFailedCount, 0)
        XCTAssertEqual(slowProvider.fetchCount, 1)
        XCTAssertEqual(fastProvider.fetchCount, 1)
        XCTAssertTrue(promoView.currentProvider === fastProvider)
    }

    func testTimedOutProviderFallsThroughToNextProvider() {
        let slowProvider = TestPromoProvider(result: .contentAvailable, completionDelay: 0.2)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate
        hostView.addSubview(promoView)

        promoView.providerFetchTimeout = 0.05

        promoView.providers = [slowProvider, fallbackProvider]

        // Wait for the fallback to fully resolve so currentProvider is settled.
        wait(for: [delegate.resolveExpectation], timeout: 1.0)
        XCTAssertEqual(slowProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 1)
        XCTAssertTrue(promoView.currentProvider === fallbackProvider)
        XCTAssertTrue(delegate.resolvedProvider === fallbackProvider)
    }

    func testLateTimedOutProviderResultIsIgnored() {
        let slowProvider = TestPromoProvider(result: .contentAvailable, completionDelay: 0.2)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        hostView.addSubview(promoView)

        promoView.providerFetchTimeout = 0.05

        let fallbackExpectation = expectation(description: "Fallback provider becomes current")
        fallbackProvider.onFetch = {
            if fallbackProvider.fetchCount == 1 {
                fallbackExpectation.fulfill()
            }
        }

        promoView.providers = [slowProvider, fallbackProvider]

        wait(for: [fallbackExpectation], timeout: 1.0)

        let lateCallbackExpectation = expectation(description: "Slow provider callback has enough time to arrive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            lateCallbackExpectation.fulfill()
        }

        wait(for: [lateCallbackExpectation], timeout: 1.0)
        XCTAssertTrue(promoView.currentProvider === fallbackProvider)
        XCTAssertEqual(slowProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 1)
    }
}
