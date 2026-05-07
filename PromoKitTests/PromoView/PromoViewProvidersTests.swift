import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoViewProvidersTests: XCTestCase {

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
}
