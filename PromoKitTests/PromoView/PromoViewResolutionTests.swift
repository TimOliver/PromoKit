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
        promoView.isLoading = true
        delegate.onResolveFailure = {
            XCTAssertFalse(promoView.isLoading, "An empty provider list must stop loading before notifying the host")
            XCTAssertNil(promoView.currentProvider)
            XCTAssertNil(promoView.contentView)
        }

        promoView.providers = []

        wait(for: [delegate.resolveFailedExpectation, delegate.fetchFailedExpectation],
             timeout: 1.0, enforceOrder: true)
        XCTAssertEqual(delegate.resolveCount, 0)
        XCTAssertEqual(delegate.resolveFailedCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 1)
        XCTAssertNil(promoView.currentProvider)
        XCTAssertFalse(promoView.isLoading)
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


extension PromoViewResolutionTests {
    func testReloadFromResolutionCallbackSurvives() {
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let first = TestPromoProvider(result: .contentAvailable)
        let second = TestPromoProvider(result: .contentAvailable)
        let delegate = PromoViewDelegateSpy()
        view.delegate = delegate
        delegate.onResolve = { provider in
            if provider === first { view.providers = [second] }
        }
        view.providers = [first]
        let settled = expectation(description: "Resolve callbacks settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(second.fetchCount, 1, "Delegate-triggered reload must not be cancelled by the old success callback")
        XCTAssertTrue(view.currentProvider === second)
    }
}


extension PromoViewResolutionTests {
    func testRemovingProvidersInvalidatesPendingManualFetch() {
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        view.reloadsAutomatically = false
        let provider = TestPromoProvider(result: .contentAvailable, completionDelay: 0.04)
        let started = expectation(description: "Old provider fetch starts")
        provider.onFetch = { started.fulfill() }
        view.providers = [provider]
        view.reload()
        wait(for: [started], timeout: 1)
        view.providers = []
        let settled = expectation(description: "Removed provider returns")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertNil(view.currentProvider, "A provider no longer assigned must not resolve")
        XCTAssertNil(view.contentView)
    }
}

extension PromoViewResolutionTests {
    func testFailedSizeRefreshClearsRemovedContentBeforeNotifyingAndAllowsRetry() throws {
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = ControlledResolutionProvider(needsReloadOnSizeChange: true)
        let delegate = PromoViewDelegateSpy()
        view.delegate = delegate
        let initialFetch = expectation(description: "Initial fetch starts")
        provider.onFetch = { initialFetch.fulfill() }
        view.providers = [provider]
        wait(for: [initialFetch], timeout: 1.0)
        try completeFetch(provider, with: .contentAvailable)
        wait(for: [delegate.updateExpectation], timeout: 1.0)
        XCTAssertNotNil(view.contentView)
        XCTAssertTrue(view.currentProvider === provider)

        let refreshFetch = expectation(description: "Size refresh starts")
        provider.onFetch = { refreshFetch.fulfill() }
        view.frame.size.width = 280
        wait(for: [refreshFetch], timeout: 1.0)
        XCTAssertNil(view.contentView, "The old content is incompatible with the new size")
        XCTAssertTrue(view.isLoading)
        delegate.onResolveFailure = {
            XCTAssertNil(view.currentProvider, "Failure observers must see no stale provider")
            XCTAssertNil(view.contentView)
            XCTAssertFalse(view.isLoading, "Failure observers must see a completed loading state")
        }

        try completeFetch(provider, with: .fetchRequestFailed)
        wait(for: [delegate.resolveFailedExpectation, delegate.fetchFailedExpectation],
             timeout: 1.0, enforceOrder: true)
        XCTAssertNil(view.currentProvider)
        XCTAssertFalse(view.isLoading)
        XCTAssertEqual(delegate.resolveFailedCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 1)
        XCTAssertEqual(delegate.updateCount, 1)

        let retryFetch = expectation(description: "The empty promo can retry")
        provider.onFetch = { retryFetch.fulfill() }
        view.reloadIfNeeded()
        wait(for: [retryFetch], timeout: 1.0)
        XCTAssertEqual(provider.fetchCount, 3)
        let retryResolved = expectation(description: "Retry resolves")
        delegate.onResolve = { _ in retryResolved.fulfill() }
        try completeFetch(provider, with: .contentAvailable)
        wait(for: [retryResolved], timeout: 1.0)
        XCTAssertTrue(view.currentProvider === provider)
        XCTAssertNotNil(view.contentView)
        XCTAssertFalse(view.isLoading)
        XCTAssertEqual(delegate.resolveFailedCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 1)
    }

    func testFailedReloadPreservesAlreadyDisplayedContentAndStopsLoading() throws {
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = ControlledResolutionProvider(needsReloadOnSizeChange: false)
        let delegate = PromoViewDelegateSpy()
        view.delegate = delegate
        let initialFetch = expectation(description: "Initial fetch starts")
        provider.onFetch = { initialFetch.fulfill() }
        view.providers = [provider]
        wait(for: [initialFetch], timeout: 1.0)
        try completeFetch(provider, with: .contentAvailable)
        wait(for: [delegate.updateExpectation], timeout: 1.0)
        let originalContent = try XCTUnwrap(view.contentView)

        let reloadFetch = expectation(description: "Reload starts")
        provider.onFetch = { reloadFetch.fulfill() }
        view.reload()
        wait(for: [reloadFetch], timeout: 1.0)
        XCTAssertTrue(view.contentView === originalContent)
        XCTAssertTrue(view.isLoading)
        delegate.onResolveFailure = {
            XCTAssertTrue(view.currentProvider === provider)
            XCTAssertTrue(view.contentView === originalContent,
                          "A failed refresh must preserve the content still on screen")
            XCTAssertFalse(view.isLoading)
        }

        try completeFetch(provider, with: .fetchRequestFailed)
        wait(for: [delegate.resolveFailedExpectation, delegate.fetchFailedExpectation],
             timeout: 1.0, enforceOrder: true)
        XCTAssertTrue(view.currentProvider === provider)
        XCTAssertTrue(view.contentView === originalContent)
        XCTAssertFalse(view.isLoading)
        XCTAssertEqual(delegate.resolveFailedCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 1)
        XCTAssertEqual(delegate.updateCount, 1, "Preserved content should not be rebuilt")
    }

    func testConsecutiveSizeChangesReplaceThePendingRequestAndIgnoreItsCompletion() throws {
        let narrowSize = CGSize(width: 320, height: 80)
        let wideSize = CGSize(width: 600, height: 80)
        let view = PromoView(frame: CGRect(origin: .zero, size: narrowSize))
        view.defaultContentPadding = .zero
        let provider = ControlledResolutionProvider(needsReloadOnSizeChange: true)
        let delegate = PromoViewDelegateSpy()
        view.delegate = delegate
        let initialFetch = expectation(description: "Initial narrow fetch starts")
        provider.onFetch = { initialFetch.fulfill() }
        view.providers = [provider]
        wait(for: [initialFetch], timeout: 1.0)
        try completeFetch(provider, with: .contentAvailable)
        wait(for: [delegate.updateExpectation], timeout: 1.0)

        let wideFetch = expectation(description: "Wide size refresh starts")
        provider.onFetch = { wideFetch.fulfill() }
        view.frame.size = wideSize
        wait(for: [wideFetch], timeout: 1.0)
        let supersededCompletion = try XCTUnwrap(provider.pendingCompletions.first)
        provider.pendingCompletions.removeFirst()

        let narrowFetch = expectation(description: "Second resize replaces the pending wide request")
        provider.onFetch = { narrowFetch.fulfill() }
        view.frame.size = narrowSize
        wait(for: [narrowFetch], timeout: 1.0)
        XCTAssertEqual(provider.requestedSizes, [narrowSize, wideSize, narrowSize])
        XCTAssertNil(view.contentView)
        XCTAssertTrue(view.isLoading)

        supersededCompletion(.contentAvailable)
        let staleCompletionDrained = expectation(description: "Superseded completion is processed")
        DispatchQueue.main.async { staleCompletionDrained.fulfill() }
        wait(for: [staleCompletionDrained], timeout: 1.0)
        XCTAssertNil(view.contentView, "A response for the intermediate width must not be displayed")
        XCTAssertTrue(view.isLoading, "The final size request is still outstanding")
        XCTAssertEqual(delegate.resolveCount, 1)
        XCTAssertEqual(delegate.updateCount, 1)

        let finalResolution = expectation(description: "The final narrow request resolves")
        delegate.onResolve = { _ in finalResolution.fulfill() }
        try completeFetch(provider, with: .contentAvailable)
        wait(for: [finalResolution], timeout: 1.0)

        XCTAssertTrue(view.currentProvider === provider)
        XCTAssertEqual(provider.displayedRequestSizes, [narrowSize, narrowSize])
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 1200, height: 1000)), narrowSize)
        XCTAssertEqual(view.contentView?.frame.size, narrowSize)
        XCTAssertFalse(view.isLoading)
        XCTAssertEqual(delegate.resolveCount, 2)
        XCTAssertEqual(delegate.updateCount, 2)
        XCTAssertEqual(delegate.resolveFailedCount, 0)
        XCTAssertEqual(delegate.fetchFailedCount, 0)
    }

    private func completeFetch(_ provider: ControlledResolutionProvider,
                               with result: PromoProviderFetchContentResult) throws {
        let completion = try XCTUnwrap(provider.pendingCompletions.first)
        provider.pendingCompletions.removeFirst()
        completion(result)
    }
}

private final class ControlledResolutionProvider: NSObject, PromoProvider {
    let needsReloadOnSizeChange: Bool
    let showsLoadingIndicatorDuringFetch = true
    var fetchCount = 0
    var onFetch: (() -> Void)?
    var pendingCompletions: [PromoProviderContentFetchHandler] = []
    private(set) var requestedSizes: [CGSize] = []
    private(set) var displayedRequestSizes: [CGSize] = []
    private var loadedSize = CGSize.zero

    init(needsReloadOnSizeChange: Bool) {
        self.needsReloadOnSizeChange = needsReloadOnSizeChange
        super.init()
    }

    func fetchNewContent(for promoView: PromoView,
                         with resultHandler: @escaping PromoProviderContentFetchHandler) {
        fetchCount += 1
        let requestedSize = promoView.bounds.size
        requestedSizes.append(requestedSize)
        pendingCompletions.append { [weak self] result in
            if result == .contentAvailable { self?.loadedSize = requestedSize }
            resultHandler(result)
        }
        onFetch?()
    }

    func contentView(for promoView: PromoView) -> PromoContentView {
        displayedRequestSizes.append(loadedSize)
        return promoView.dequeueContentView(for: TestPromoContentView.self)
    }

    func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        loadedSize
    }
}

extension PromoViewResolutionTests {
    func testInitialSizeSensitiveFetchIsReplacedWhenBoundsChange() throws {
        let narrow = CGSize(width: 320, height: 80)
        let wide = CGSize(width: 600, height: 80)
        let view = PromoView(frame: CGRect(origin: .zero, size: narrow))
        view.defaultContentPadding = .zero
        let provider = ControlledResolutionProvider(needsReloadOnSizeChange: true)
        let delegate = PromoViewDelegateSpy()
        view.delegate = delegate
        let initialStarted = expectation(description: "Initial size-sensitive request starts")
        provider.onFetch = { initialStarted.fulfill() }
        view.providers = [provider]
        wait(for: [initialStarted], timeout: 1.0)
        let obsoleteCompletion = try XCTUnwrap(provider.pendingCompletions.first)
        provider.pendingCompletions.removeFirst()
        provider.onFetch = nil

        view.bounds.size = wide
        let resizeProcessed = expectation(description: "Resize-triggered request can start")
        DispatchQueue.main.async { resizeProcessed.fulfill() }
        wait(for: [resizeProcessed], timeout: 1.0)
        XCTAssertEqual(provider.requestedSizes, [narrow, wide],
                       "Resizing during the first load must replace the request just as a later resize does")

        obsoleteCompletion(.contentAvailable)
        let obsoleteProcessed = expectation(description: "Obsolete response is handled")
        DispatchQueue.main.async { obsoleteProcessed.fulfill() }
        wait(for: [obsoleteProcessed], timeout: 1.0)
        XCTAssertNil(view.contentView, "The response sized for the old bounds must not be displayed")
        XCTAssertTrue(provider.displayedRequestSizes.isEmpty)
        XCTAssertEqual(delegate.updateCount, 0)

        let finalResolved = expectation(description: "The request for the new bounds resolves")
        delegate.onResolve = { _ in finalResolved.fulfill() }
        try completeFetch(provider, with: .contentAvailable)
        wait(for: [finalResolved], timeout: 1.0)
        XCTAssertEqual(provider.displayedRequestSizes, [wide])
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 1200, height: 1000)), wide)
        XCTAssertEqual(delegate.updateCount, 1)
    }
}
