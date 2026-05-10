import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoProviderCoordinatorTests: XCTestCase {

    func testProviderForClassReturnsMatchingConcreteProvider() {
        let firstProvider = TestPromoProvider(result: .contentAvailable)
        let secondProvider = ReuseTrackingPromoProvider()
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        coordinator.providers = [firstProvider, secondProvider]

        XCTAssertTrue(coordinator.providerForClass(TestPromoProvider.self) === firstProvider)
        XCTAssertTrue(coordinator.providerForClass(ReuseTrackingPromoProvider.self) === secondProvider)
        XCTAssertNil(coordinator.providerForClass(UIView.self))
    }

    func testFetchBestProviderWithNoProvidersReportsNilWithoutFetching() {
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = []

        let noProviderResolved = expectResolution(in: resolutions,
                                                  description: "Coordinator resolves nil for an empty provider list") {
            $0 == nil
        }
        coordinator.fetchBestProvider()

        wait(for: [noProviderResolved], timeout: 1.0)
        XCTAssertFalse(coordinator.isFetching)
        XCTAssertNil(coordinator.currentProvider)
        XCTAssertEqual(resolutions.resolvedProviders.count, 1)
    }

    func testFetchBestProviderStartsAtRequestedProvider() {
        let firstProvider = TestPromoProvider(result: .contentAvailable)
        let secondProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [firstProvider, secondProvider]

        let secondResolved = expectResolution(in: resolutions,
                                              description: "Coordinator resolves the requested starting provider") {
            $0 === secondProvider
        }
        coordinator.fetchBestProvider(from: secondProvider)

        wait(for: [secondResolved], timeout: 1.0)
        XCTAssertEqual(firstProvider.fetchCount, 0)
        XCTAssertEqual(secondProvider.fetchCount, 1)
        XCTAssertTrue(coordinator.currentProvider === secondProvider)
    }

    func testProviderReceivesPromoViewAndShowsLoadingIndicatorBeforeFetch() {
        let provider = TestPromoProvider(result: .contentAvailable,
                                         showsLoadingIndicatorDuringFetch: true,
                                         completes: false)
        let fixture = makeCoordinator()
        let promoView = fixture.promoView
        let coordinator = fixture.coordinator
        coordinator.fetchTimeout = 0
        coordinator.providers = [provider]

        coordinator.fetchBestProvider()

        XCTAssertTrue(provider.lastPromoView === promoView)
        XCTAssertEqual(provider.didMoveToPromoViewCount, 1)
        XCTAssertTrue(promoView.isLoading)
        coordinator.cancelFetch()
    }

    func testProviderReturningNoContentFallsThroughToNextProvider() {
        let emptyProvider = TestPromoProvider(result: .noContentAvailable)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [emptyProvider, fallbackProvider]

        let fallbackResolved = expectResolution(in: resolutions,
                                                description: "Coordinator resolves fallback provider") {
            $0 === fallbackProvider
        }
        coordinator.fetchBestProvider()

        wait(for: [fallbackResolved], timeout: 1.0)
        XCTAssertEqual(emptyProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 1)
        XCTAssertEqual(result(for: emptyProvider, in: coordinator), .noContentAvailable)
        XCTAssertTrue(coordinator.currentProvider === fallbackProvider)
    }

    func testExhaustingProvidersInvokesFetchFailedHandler() {
        let emptyProvider = TestPromoProvider(result: .noContentAvailable)
        let failingProvider = TestPromoProvider(result: .fetchRequestFailed)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        coordinator.providers = [emptyProvider, failingProvider]

        let fetchFailed = expectation(description: "Coordinator reports provider fetch failure")
        coordinator.providerFetchFailedHandler = { fetchFailed.fulfill() }

        coordinator.fetchBestProvider()

        wait(for: [fetchFailed], timeout: 1.0)
        XCTAssertFalse(coordinator.isFetching)
        XCTAssertNil(coordinator.currentProvider)
        XCTAssertEqual(emptyProvider.fetchCount, 1)
        XCTAssertEqual(failingProvider.fetchCount, 1)
        XCTAssertEqual(result(for: failingProvider, in: coordinator), .fetchRequestFailed)
    }

    func testInternetProviderWithOfflineCacheIsEligibleWhileDisconnected() {
        let cachedOnlineProvider = TestPromoProvider(result: .contentAvailable,
                                                     isInternetAccessRequired: true,
                                                     isOfflineCacheAvailable: true)
        let fixture = makeCoordinator(connected: false)
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [cachedOnlineProvider]

        let cachedProviderResolved = expectResolution(in: resolutions,
                                                      description: "Coordinator resolves cached online provider offline") {
            $0 === cachedOnlineProvider
        }
        coordinator.fetchBestProvider()

        wait(for: [cachedProviderResolved], timeout: 1.0)
        XCTAssertEqual(cachedOnlineProvider.fetchCount, 1)
        XCTAssertTrue(coordinator.currentProvider === cachedOnlineProvider)
    }

    func testCoordinatorReFetchesWhenNetworkRecoversFromOffline() {
        let stubMonitor = StubPathMonitor(connected: false)
        let onlineProvider = TestPromoProvider(result: .contentAvailable, isInternetAccessRequired: true)
        let offlineProvider = TestPromoProvider(result: .contentAvailable, isOfflineCacheAvailable: true)

        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let coordinator = PromoProviderCoordinator(promoView: promoView, networkMonitor: stubMonitor)

        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [onlineProvider, offlineProvider]
        coordinator.fetchBestProvider()

        let initialResolved = expectation(description: "Offline provider resolves while disconnected")
        resolutions.onUpdate = { provider in
            if provider === offlineProvider { initialResolved.fulfill() }
        }
        wait(for: [initialResolved], timeout: 1.0)
        XCTAssertEqual(onlineProvider.fetchCount, 0,
                       "Online provider must be filtered out while disconnected")

        let onlineResolved = expectation(description: "Online provider takes over after network recovers")
        resolutions.onUpdate = { provider in
            if provider === onlineProvider { onlineResolved.fulfill() }
        }
        stubMonitor.simulateConnectivityChange(true)

        wait(for: [onlineResolved], timeout: 1.0)
        XCTAssertTrue(coordinator.currentProvider === onlineProvider)
        XCTAssertEqual(onlineProvider.fetchCount, 1)
    }

    func testCoordinatorSwitchesToOfflineProviderWhenNetworkDrops() {
        let stubMonitor = StubPathMonitor(connected: true)
        let onlineProvider = TestPromoProvider(result: .contentAvailable, isInternetAccessRequired: true)
        let offlineProvider = TestPromoProvider(result: .contentAvailable)

        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let coordinator = PromoProviderCoordinator(promoView: promoView, networkMonitor: stubMonitor)

        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [onlineProvider, offlineProvider]

        let onlineResolved = expectResolution(in: resolutions,
                                              description: "Online provider resolves while connected") {
            $0 === onlineProvider
        }
        coordinator.fetchBestProvider()
        wait(for: [onlineResolved], timeout: 1.0)

        let offlineResolved = expectResolution(in: resolutions,
                                               description: "Offline provider resolves after network drops") {
            $0 === offlineProvider
        }
        stubMonitor.simulateConnectivityChange(false)

        wait(for: [offlineResolved], timeout: 1.0)
        XCTAssertTrue(coordinator.currentProvider === offlineProvider)
        XCTAssertEqual(onlineProvider.fetchCount, 1)
        XCTAssertEqual(offlineProvider.fetchCount, 1)
    }

    func testCoordinatorDoesNotRefetchInternetProviderWhenNetworkStillConnected() {
        let stubMonitor = StubPathMonitor(connected: true)
        let onlineProvider = TestPromoProvider(result: .contentAvailable, isInternetAccessRequired: true)

        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let coordinator = PromoProviderCoordinator(promoView: promoView, networkMonitor: stubMonitor)
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [onlineProvider]

        let onlineResolved = expectResolution(in: resolutions,
                                              description: "Online provider resolves") {
            $0 === onlineProvider
        }
        coordinator.fetchBestProvider()
        wait(for: [onlineResolved], timeout: 1.0)

        let unexpectedRefetch = expectation(description: "Connected online provider is not refetched")
        unexpectedRefetch.isInverted = true
        onlineProvider.onFetch = {
            if onlineProvider.fetchCount > 1 {
                unexpectedRefetch.fulfill()
            }
        }
        stubMonitor.simulateConnectivityChange(true)

        wait(for: [unexpectedRefetch], timeout: 0.1)
        XCTAssertEqual(onlineProvider.fetchCount, 1)
    }

    func testCoordinatorIgnoresConnectivityChangesWithNoCurrentProvider() {
        let stubMonitor = StubPathMonitor(connected: true)
        let provider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let coordinator = PromoProviderCoordinator(promoView: promoView, networkMonitor: stubMonitor)
        coordinator.providers = [provider]

        // No fetchBestProvider call yet — currentProvider is nil. A connectivity change must
        // not start a fetch on its own; only an existing provider triggers a re-evaluation.
        stubMonitor.simulateConnectivityChange(false)
        stubMonitor.simulateConnectivityChange(true)

        let settle = expectation(description: "Run loop spins after connectivity changes")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
        XCTAssertEqual(provider.fetchCount, 0)
    }

    func testFailedProviderIsSkippedUntilRetryIntervalElapses() {
        let failingProvider = TestPromoProvider(result: .fetchRequestFailed)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.retryInterval = 100
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [failingProvider, fallbackProvider]

        let fallbackResolved = expectResolution(in: resolutions,
                                                description: "Fallback resolves after the first provider fails") {
            $0 === fallbackProvider
        }
        coordinator.fetchBestProvider()
        wait(for: [fallbackResolved], timeout: 1.0)

        let fallbackResolvedAgain = expectResolution(in: resolutions,
                                                     description: "Fallback resolves again while failed provider is cooling down") {
            $0 === fallbackProvider && fallbackProvider.fetchCount == 2
        }
        coordinator.fetchBestProvider()

        wait(for: [fallbackResolvedAgain], timeout: 1.0)
        XCTAssertEqual(failingProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 2)
    }

    func testFailedProviderIsFetchedAgainAfterRetryIntervalElapses() {
        let failingProvider = TestPromoProvider(result: .fetchRequestFailed)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.retryInterval = 100
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [failingProvider, fallbackProvider]

        let fallbackResolved = expectResolution(in: resolutions,
                                                description: "Fallback resolves after failure") {
            $0 === fallbackProvider
        }
        coordinator.fetchBestProvider()
        wait(for: [fallbackResolved], timeout: 1.0)

        coordinator.providerFetchDates.setObject(Date(timeIntervalSinceNow: -101) as NSDate,
                                                 forKey: failingProvider)

        let failingProviderFetchedAgain = expectation(description: "Failed provider is fetched after retry interval")
        failingProvider.onFetch = {
            if failingProvider.fetchCount == 2 {
                failingProviderFetchedAgain.fulfill()
            }
        }
        let fallbackResolvedAgain = expectResolution(in: resolutions,
                                                     description: "Fallback resolves after second failure") {
            $0 === fallbackProvider && fallbackProvider.fetchCount == 2
        }
        coordinator.fetchBestProvider()

        wait(for: [failingProviderFetchedAgain, fallbackResolvedAgain], timeout: 1.0)
        XCTAssertEqual(failingProvider.fetchCount, 2)
        XCTAssertEqual(fallbackProvider.fetchCount, 2)
    }

    func testContentProviderIsSkippedUntilRefreshIntervalElapses() {
        let cachedProvider = TestPromoProvider(result: .contentAvailable, fetchRefreshInterval: 100)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [cachedProvider, fallbackProvider]

        let cachedProviderResolved = expectResolution(in: resolutions,
                                                      description: "Primary provider resolves") {
            $0 === cachedProvider
        }
        coordinator.fetchBestProvider()
        wait(for: [cachedProviderResolved], timeout: 1.0)

        let fallbackResolved = expectResolution(in: resolutions,
                                                description: "Fallback resolves while primary provider is fresh") {
            $0 === fallbackProvider
        }
        coordinator.fetchBestProvider()

        wait(for: [fallbackResolved], timeout: 1.0)
        XCTAssertEqual(cachedProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 1)
        XCTAssertTrue(coordinator.currentProvider === fallbackProvider)
    }

    func testContentProviderIsFetchedAgainAfterRefreshIntervalElapses() {
        let cachedProvider = TestPromoProvider(result: .contentAvailable, fetchRefreshInterval: 100)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [cachedProvider, fallbackProvider]

        let cachedProviderResolved = expectResolution(in: resolutions,
                                                      description: "Primary provider resolves") {
            $0 === cachedProvider
        }
        coordinator.fetchBestProvider()
        wait(for: [cachedProviderResolved], timeout: 1.0)

        coordinator.providerFetchDates.setObject(Date(timeIntervalSinceNow: -101) as NSDate,
                                                 forKey: cachedProvider)

        let cachedProviderFetchedAgain = expectation(description: "Primary provider is fetched after refresh interval")
        cachedProvider.onFetch = {
            if cachedProvider.fetchCount == 2 {
                cachedProviderFetchedAgain.fulfill()
            }
        }
        let cachedProviderResolvedAgain = expectResolution(in: resolutions,
                                                          description: "Primary provider resolves after refresh interval") {
            $0 === cachedProvider && cachedProvider.fetchCount == 2
        }
        coordinator.fetchBestProvider()

        wait(for: [cachedProviderFetchedAgain, cachedProviderResolvedAgain], timeout: 1.0)
        XCTAssertEqual(cachedProvider.fetchCount, 2)
        XCTAssertEqual(fallbackProvider.fetchCount, 0)
        XCTAssertTrue(coordinator.currentProvider === cachedProvider)
    }

    func testResetClearsFetchHistoryAndAllowsImmediateRefetch() {
        let cachedProvider = TestPromoProvider(result: .contentAvailable, fetchRefreshInterval: 100)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [cachedProvider]

        let cachedProviderResolved = expectResolution(in: resolutions,
                                                      description: "Primary provider resolves") {
            $0 === cachedProvider
        }
        coordinator.fetchBestProvider()
        wait(for: [cachedProviderResolved], timeout: 1.0)
        XCTAssertNotNil(result(for: cachedProvider, in: coordinator))

        coordinator.reset()
        XCTAssertNil(result(for: cachedProvider, in: coordinator))

        let cachedProviderFetchedAgain = expectation(description: "Provider is fetched again after reset")
        cachedProvider.onFetch = {
            if cachedProvider.fetchCount == 2 {
                cachedProviderFetchedAgain.fulfill()
            }
        }
        let cachedProviderResolvedAgain = expectResolution(in: resolutions,
                                                          description: "Provider resolves again after reset") {
            $0 === cachedProvider && cachedProvider.fetchCount == 2
        }
        coordinator.fetchBestProvider()

        wait(for: [cachedProviderFetchedAgain, cachedProviderResolvedAgain], timeout: 1.0)
        XCTAssertEqual(cachedProvider.fetchCount, 2)
    }

    func testCancelFetchIgnoresLateProviderCompletion() {
        let slowProvider = TestPromoProvider(result: .contentAvailable, completionDelay: 0.05)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        coordinator.providers = [slowProvider]

        let unexpectedResolution = expectation(description: "Canceled provider completion is ignored")
        unexpectedResolution.isInverted = true
        coordinator.providerUpdatedHandler = { _ in unexpectedResolution.fulfill() }

        let fetchStarted = expectation(description: "Slow provider fetch starts")
        slowProvider.onFetch = { fetchStarted.fulfill() }
        coordinator.fetchBestProvider()
        wait(for: [fetchStarted], timeout: 1.0)

        coordinator.cancelFetch()

        wait(for: [unexpectedResolution], timeout: 0.15)
        XCTAssertFalse(coordinator.isFetching)
        XCTAssertNil(coordinator.currentProvider)
    }

    func testTimeoutTreatsProviderAsFailedAndContinuesToNextProvider() {
        let slowProvider = TestPromoProvider(result: .contentAvailable, completionDelay: 0.08)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        let resolutions = ProviderResolutionRecorder()
        coordinator.fetchTimeout = 0.01
        coordinator.providerUpdatedHandler = { resolutions.record($0) }
        coordinator.providers = [slowProvider, fallbackProvider]

        let fallbackResolved = expectResolution(in: resolutions,
                                                description: "Fallback resolves after slow provider times out") {
            $0 === fallbackProvider
        }
        coordinator.fetchBestProvider()

        wait(for: [fallbackResolved], timeout: 1.0)
        XCTAssertEqual(result(for: slowProvider, in: coordinator), .fetchRequestFailed)
        XCTAssertTrue(coordinator.currentProvider === fallbackProvider)

        waitForDelay(0.12, description: "Late slow-provider completion has time to arrive")
        XCTAssertEqual(result(for: slowProvider, in: coordinator), .fetchRequestFailed)
        XCTAssertTrue(coordinator.currentProvider === fallbackProvider)
    }

    func testFetchTimeoutCanBeDisabled() {
        let neverCompletingProvider = TestPromoProvider(result: .contentAvailable, completes: false)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let fixture = makeCoordinator()
        let coordinator = fixture.coordinator
        coordinator.fetchTimeout = 0
        coordinator.providers = [neverCompletingProvider, fallbackProvider]

        let fetchStarted = expectation(description: "Never-completing provider fetch starts")
        neverCompletingProvider.onFetch = { fetchStarted.fulfill() }
        coordinator.fetchBestProvider()
        wait(for: [fetchStarted], timeout: 1.0)

        waitForDelay(0.05, description: "Disabled timeout leaves active fetch alone")
        XCTAssertTrue(coordinator.isFetching)
        XCTAssertEqual(neverCompletingProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 0)
        XCTAssertNil(coordinator.currentProvider)
        coordinator.cancelFetch()
    }

    private func makeCoordinator(connected: Bool = true) -> CoordinatorFixture {
        let fixture = CoordinatorFixture(connected: connected)
        addTeardownBlock { _ = fixture }
        return fixture
    }

    @MainActor
    private final class CoordinatorFixture {
        let promoView: PromoView
        let monitor: StubPathMonitor
        let coordinator: PromoProviderCoordinator

        init(connected: Bool) {
            monitor = StubPathMonitor(connected: connected)
            promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
            coordinator = PromoProviderCoordinator(promoView: promoView, networkMonitor: monitor)
        }
    }

    private func expectResolution(in recorder: ProviderResolutionRecorder,
                                  description: String,
                                  matching predicate: @escaping (PromoProvider?) -> Bool) -> XCTestExpectation {
        let resolution = expectation(description: description)
        recorder.onUpdate = { provider in
            if predicate(provider) {
                resolution.fulfill()
            }
        }
        return resolution
    }

    private func result(for provider: PromoProvider,
                        in coordinator: PromoProviderCoordinator) -> PromoProviderFetchContentResult? {
        guard let rawValue = coordinator.providerFetchResults.object(forKey: provider)?.intValue else {
            return nil
        }
        return PromoProviderFetchContentResult(rawValue: rawValue)
    }

    private func waitForDelay(_ delay: TimeInterval, description: String) {
        let settled = expectation(description: description)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: delay + 1.0)
    }
}
