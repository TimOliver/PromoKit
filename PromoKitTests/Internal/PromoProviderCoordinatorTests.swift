import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoProviderCoordinatorTests: XCTestCase {

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
}
