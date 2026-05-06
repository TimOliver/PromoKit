import XCTest
import UIKit
import CloudKit
@testable import PromoKit

@MainActor
final class PromoKitBehaviorTests: XCTestCase {

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

    func testReloadContentViewReusesQueuedContentViews() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let provider = ReuseTrackingPromoProvider()

        promoView.currentProvider = provider
        promoView.reloadContentView()
        promoView.reloadContentView()

        XCTAssertEqual(provider.contentViewIdentifiers.count, 2)
        XCTAssertEqual(provider.contentViewIdentifiers[0], provider.contentViewIdentifiers[1])
    }

    func testSizeChangeRefetchesProviderAfterRefreshIntervalExpires() {
        let provider = TestPromoProvider(result: .contentAvailable,
                                         isInternetAccessRequired: true,
                                         isOfflineCacheAvailable: true,
                                         needsReloadOnSizeChange: true,
                                         fetchRefreshInterval: 0.1)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        hostView.addSubview(promoView)

        let firstFetchExpectation = expectation(description: "Initial fetch completes")
        provider.onFetch = {
            if provider.fetchCount == 1 {
                firstFetchExpectation.fulfill()
            }
        }

        promoView.providers = [provider]
        wait(for: [firstFetchExpectation], timeout: 1.0)

        let secondFetchExpectation = expectation(description: "Provider is re-fetched after its refresh interval")
        provider.onFetch = {
            if provider.fetchCount == 2 {
                secondFetchExpectation.fulfill()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            promoView.frame.size = CGSize(width: 260, height: 80)
        }

        wait(for: [secondFetchExpectation], timeout: 1.0)
        XCTAssertEqual(provider.fetchCount, 2)
    }

    func testCloudEventVersionEligibilityUsesInclusiveBounds() {
        XCTAssertTrue(PromoCloudEventProvider.isVersionEligible("2.0.0",
                                                                minVersion: "1.0.0",
                                                                maxVersion: "2.0.0"))
        XCTAssertTrue(PromoCloudEventProvider.isVersionEligible("2.0.0",
                                                                minVersion: "2.0.0",
                                                                maxVersion: "3.0.0"))
        XCTAssertFalse(PromoCloudEventProvider.isVersionEligible("1.9.9", minVersion: "2.0.0"))
        XCTAssertFalse(PromoCloudEventProvider.isVersionEligible("3.0.1", maxVersion: "3.0.0"))
    }

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

    // MARK: - Resolution callback hardening

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

    func testAssigningProvidersClearsCurrentWhenItIsNoLongerInTheList() {
        let firstProvider = TestPromoProvider(result: .contentAvailable)
        let replacementProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        let firstResolved = expectation(description: "First provider resolves")
        delegate.onResolve = { provider in
            if provider === firstProvider { firstResolved.fulfill() }
        }
        promoView.providers = [firstProvider]
        wait(for: [firstResolved], timeout: 1.0)
        XCTAssertNotNil(promoView.contentView)

        // Reassigning to a list that doesn't contain firstProvider should drop the current
        // provider synchronously, before the new reload's async fetch even runs.
        promoView.providers = [replacementProvider]
        XCTAssertNil(promoView.currentProvider)
        XCTAssertNil(promoView.contentView)
    }

    func testAssigningProvidersKeepsCurrentWhenItIsStillInTheList() {
        let keeper = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promoView.reloadsAutomatically = false
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        promoView.providers = [keeper]
        promoView.reload()

        let resolved = expectation(description: "Keeper resolves")
        delegate.onResolve = { provider in
            if provider === keeper { resolved.fulfill() }
        }
        wait(for: [resolved], timeout: 1.0)

        // Adding a higher-priority provider in front shouldn't drop the keeper —
        // it's still in the list, so currentProvider must survive the reassignment.
        let higherPriority = TestPromoProvider(result: .contentAvailable)
        promoView.providers = [higherPriority, keeper]
        XCTAssertTrue(promoView.currentProvider === keeper)
        XCTAssertNotNil(promoView.contentView)
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

    func testRefreshIntervalSkipKeepsCurrentProviderVisible() {
        let provider = TestPromoProvider(result: .contentAvailable,
                                         needsReloadOnSizeChange: true,
                                         fetchRefreshInterval: 60.0)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate
        hostView.addSubview(promoView)

        let initialFetchExpectation = expectation(description: "Initial provider loads")
        provider.onFetch = {
            if provider.fetchCount == 1 {
                initialFetchExpectation.fulfill()
            }
        }

        promoView.providers = [provider]
        wait(for: [initialFetchExpectation], timeout: 1.0)

        promoView.frame.size = CGSize(width: 260, height: 80)

        let noOpExpectation = expectation(description: "Coordinator finishes without clearing current content")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            noOpExpectation.fulfill()
        }

        wait(for: [noOpExpectation], timeout: 1.0)
        XCTAssertTrue(promoView.currentProvider === provider)
        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(delegate.fetchFailedCount, 0)
    }

    func testCloudEventQueryPredicateAllowsRecordsWithoutExpirationDate() {
        // Asserting on the predicate's behavior rather than its `predicateFormat` string —
        // NSPredicate normalizes the format differently across iOS versions (NULL → nil,
        // for example), so format matching becomes brittle without adding any safety.
        let predicate = PromoCloudEventProvider.eventQueryPredicate(eventType: "app-update")

        let recordWithoutExpiry: NSDictionary = ["type": "app-update"]
        let recordWithFutureExpiry: NSDictionary = [
            "type": "app-update",
            "expirationDate": Date().addingTimeInterval(60)
        ]
        let recordWithPastExpiry: NSDictionary = [
            "type": "app-update",
            "expirationDate": Date().addingTimeInterval(-60)
        ]
        let recordWithMismatchedType: NSDictionary = ["type": "other"]

        XCTAssertTrue(predicate.evaluate(with: recordWithoutExpiry),
                      "Records without an expirationDate should remain eligible")
        XCTAssertTrue(predicate.evaluate(with: recordWithFutureExpiry),
                      "Records with a future expirationDate should be eligible")
        XCTAssertFalse(predicate.evaluate(with: recordWithPastExpiry),
                       "Records past their expirationDate should be filtered out")
        XCTAssertFalse(predicate.evaluate(with: recordWithMismatchedType),
                       "Records of a different type should be filtered out")
    }

    func testCloudEventRecordPreferencePrefersExpiringRecords() {
        let expiringRecord = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "expiring"))
        expiringRecord["expirationDate"] = Date().addingTimeInterval(60) as NSDate

        let nonExpiringRecord = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "non-expiring"))

        XCTAssertTrue(PromoCloudEventProvider.isRecordPreferred(expiringRecord, over: nonExpiringRecord))
        XCTAssertFalse(PromoCloudEventProvider.isRecordPreferred(nonExpiringRecord, over: expiringRecord))

        let laterExpiringRecord = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "later"))
        laterExpiringRecord["expirationDate"] = Date().addingTimeInterval(120) as NSDate

        XCTAssertTrue(PromoCloudEventProvider.isRecordPreferred(expiringRecord, over: laterExpiringRecord))
        XCTAssertFalse(PromoCloudEventProvider.isRecordPreferred(laterExpiringRecord, over: expiringRecord))
    }

    func testCloudEventReplaceCachedFileOverwritesAndRemovesOldData() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let cacheURL = temporaryDirectory.appendingPathComponent("thumbnail.cache")
        let sourceURL = temporaryDirectory.appendingPathComponent("thumbnail.new")
        try Data("old".utf8).write(to: cacheURL)
        try Data("new".utf8).write(to: sourceURL)

        PromoCloudEventProvider.replaceCachedFile(at: cacheURL, with: sourceURL)
        XCTAssertEqual(try String(contentsOf: cacheURL), "new")

        PromoCloudEventProvider.replaceCachedFile(at: cacheURL, with: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
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

private final class TestPromoProvider: NSObject, PromoProvider {
    let result: PromoProviderFetchContentResult
    let isInternetAccessRequired: Bool
    let isOfflineCacheAvailable: Bool
    let needsReloadOnSizeChange: Bool
    let fetchRefreshInterval: TimeInterval
    let completionDelay: TimeInterval
    let completes: Bool

    var fetchCount = 0
    var onFetch: (() -> Void)?

    init(result: PromoProviderFetchContentResult,
         isInternetAccessRequired: Bool = false,
         isOfflineCacheAvailable: Bool = false,
         needsReloadOnSizeChange: Bool = false,
         fetchRefreshInterval: TimeInterval = 0,
         completionDelay: TimeInterval = 0,
         completes: Bool = true) {
        self.result = result
        self.isInternetAccessRequired = isInternetAccessRequired
        self.isOfflineCacheAvailable = isOfflineCacheAvailable
        self.needsReloadOnSizeChange = needsReloadOnSizeChange
        self.fetchRefreshInterval = fetchRefreshInterval
        self.completionDelay = completionDelay
        self.completes = completes
    }

    func fetchNewContent(for promoView: PromoView,
                         with resultHandler: @escaping PromoProviderContentFetchHandler) {
        fetchCount += 1
        onFetch?()
        guard completes else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) {
            resultHandler(self.result)
        }
    }

    func contentView(for promoView: PromoView) -> PromoContentView {
        promoView.dequeueContentView(for: TestPromoContentView.self)
    }

    func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        CGSize(width: fittingSize.width, height: min(80, fittingSize.height))
    }
}

private final class ReuseTrackingPromoProvider: NSObject, PromoProvider {
    var contentViewIdentifiers = [ObjectIdentifier]()

    func fetchNewContent(for promoView: PromoView,
                         with resultHandler: @escaping PromoProviderContentFetchHandler) {
        resultHandler(.contentAvailable)
    }

    func contentView(for promoView: PromoView) -> PromoContentView {
        let contentView = promoView.dequeueContentView(for: TestPromoContentView.self)
        contentViewIdentifiers.append(ObjectIdentifier(contentView))
        return contentView
    }
}

private final class PromoViewDelegateSpy: NSObject, PromoViewDelegate {
    let fetchFailedExpectation = XCTestExpectation(description: "Promo view reports fetch failure")
    let resolveExpectation = XCTestExpectation(description: "Promo view reports provider resolution")
    let resolveFailedExpectation = XCTestExpectation(description: "Promo view reports provider resolution failure")
    let updateExpectation = XCTestExpectation(description: "Promo view displays content")
    var fetchFailedCount = 0
    var resolveCount = 0
    var resolveFailedCount = 0
    var updateCount = 0
    var resolvedProvider: PromoProvider?
    var updatedProvider: PromoProvider?
    var onResolve: ((PromoProvider) -> Void)?
    var onResolveFailure: (() -> Void)?

    override init() {
        super.init()
        // Tests reuse the spy across multiple resolution cycles (e.g. resolve, then swap
        // providers and resolve again). Counts are the source of truth for exactness;
        // expectations only signal "at least one occurrence has happened by now".
        fetchFailedExpectation.assertForOverFulfill = false
        resolveExpectation.assertForOverFulfill = false
        resolveFailedExpectation.assertForOverFulfill = false
        updateExpectation.assertForOverFulfill = false
    }

    func promoViewProviderFetchFailed(_ promoView: PromoView) {
        fetchFailedCount += 1
        fetchFailedExpectation.fulfill()
    }

    func promoView(_ promoView: PromoView, didResolveProvider provider: PromoProvider) {
        resolveCount += 1
        resolvedProvider = provider
        resolveExpectation.fulfill()
        onResolve?(provider)
    }

    func promoViewDidFailToResolveProvider(_ promoView: PromoView) {
        resolveFailedCount += 1
        resolveFailedExpectation.fulfill()
        onResolveFailure?()
    }

    func promoView(_ promoView: PromoView, didUpdateProvider provider: PromoProvider) {
        updateCount += 1
        updatedProvider = provider
        updateExpectation.fulfill()
    }
}

private final class TestPromoContentView: PromoContentView {
    required init(promoView: PromoView) {
        super.init(promoView: promoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
