import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoKitBehaviorTests: XCTestCase {

    func testPromoViewStartsLoadingAfterBeingAttached() {
        let provider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80), providers: [provider])
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        let fetchExpectation = expectation(description: "Fetch starts after attaching to a superview")
        provider.onFetch = {
            fetchExpectation.fulfill()
        }

        hostView.addSubview(promoView)

        wait(for: [fetchExpectation], timeout: 1.0)
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

    func testTimedOutProviderFallsThroughToNextProvider() {
        let slowProvider = TestPromoProvider(result: .contentAvailable, completionDelay: 0.2)
        let fallbackProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        hostView.addSubview(promoView)

        promoView.providerFetchTimeout = 0.05

        let fallbackExpectation = expectation(description: "Fallback provider loads after the first provider times out")
        fallbackProvider.onFetch = {
            if fallbackProvider.fetchCount == 1 {
                fallbackExpectation.fulfill()
            }
        }

        promoView.providers = [slowProvider, fallbackProvider]

        wait(for: [fallbackExpectation], timeout: 1.0)
        XCTAssertEqual(slowProvider.fetchCount, 1)
        XCTAssertEqual(fallbackProvider.fetchCount, 1)
        XCTAssertTrue(promoView.currentProvider === fallbackProvider)
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

private final class TestPromoContentView: PromoContentView {
    required init(promoView: PromoView) {
        super.init(promoView: promoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
