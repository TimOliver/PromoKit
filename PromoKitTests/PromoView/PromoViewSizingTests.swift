import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoViewSizingTests: XCTestCase {

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

    func testSizeThatFitsWithProviderClassUsesNamedProviderForSizing() {
        let firstProvider = TestPromoProvider(result: .contentAvailable)
        let secondProvider = FixedSizePromoProvider(width: 120, height: 30)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        promoView.reloadsAutomatically = false
        promoView.providers = [firstProvider, secondProvider]

        let fittingSize = CGSize(width: 240, height: 80)
        let sizedToFirst = promoView.sizeThatFits(fittingSize, providerClass: TestPromoProvider.self)
        let sizedToSecond = promoView.sizeThatFits(fittingSize, providerClass: FixedSizePromoProvider.self)

        // Falling back to nil class should defer to the default sizeThatFits path.
        let fallbackSize = promoView.sizeThatFits(fittingSize, providerClass: nil)

        // Sizing pipeline subtracts padding before asking the provider, then re-adds it
        // to the returned size — so the fixed provider's 120x30 surfaces as 120+padding.
        let padding = promoView.defaultContentPadding
        let expectedSecondSize = CGSize(width: 120 + padding.left + padding.right,
                                        height: 30 + padding.top + padding.bottom)
        XCTAssertEqual(sizedToFirst.height, min(80, fittingSize.height))
        XCTAssertEqual(sizedToSecond, expectedSecondSize)
        XCTAssertEqual(fallbackSize.height, min(80, fittingSize.height))
    }

    func testRefreshIntervalSkipAdvancesToNextEligibleProvider() {
        let firstProvider = TestPromoProvider(result: .contentAvailable,
                                              needsReloadOnSizeChange: true,
                                              fetchRefreshInterval: 60.0)
        let secondProvider = TestPromoProvider(result: .contentAvailable)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        hostView.addSubview(promoView)
        let delegate = PromoViewDelegateSpy()
        promoView.delegate = delegate

        let firstResolved = expectation(description: "First provider resolves")
        delegate.onResolve = { provider in
            if provider === firstProvider { firstResolved.fulfill() }
        }
        promoView.providers = [firstProvider, secondProvider]
        wait(for: [firstResolved], timeout: 1.0)

        // Size change triggers a re-fetch starting from the current provider; the refresh
        // interval skip should advance to the second provider rather than re-querying the first.
        let secondResolved = expectation(description: "Second provider resolves after first is skipped")
        delegate.onResolve = { provider in
            if provider === secondProvider { secondResolved.fulfill() }
        }
        promoView.frame.size = CGSize(width: 260, height: 80)

        wait(for: [secondResolved], timeout: 1.0)
        XCTAssertTrue(promoView.currentProvider === secondProvider)
        XCTAssertEqual(firstProvider.fetchCount, 1)
        XCTAssertEqual(secondProvider.fetchCount, 1)
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
}
