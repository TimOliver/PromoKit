import XCTest
@testable import PromoKit

/// `PromoViewDelegate` double that records every callback invocation. Counts are the
/// authoritative signal for "fired exactly N times" assertions; the `XCTestExpectation`
/// fields just signal "at least one occurrence has happened by now". Multi-cycle tests
/// (resolve then re-resolve) re-use the spy without re-creating it, so over-fulfillment
/// of the expectations is intentionally allowed.
final class PromoViewDelegateSpy: NSObject, PromoViewDelegate {
    let fetchFailedExpectation = XCTestExpectation(description: "Promo view reports fetch failure")
    let resolveExpectation = XCTestExpectation(description: "Promo view reports provider resolution")
    let resolveFailedExpectation = XCTestExpectation(description: "Promo view reports provider resolution failure")
    let updateExpectation = XCTestExpectation(description: "Promo view displays content")
    var fetchFailedCount = 0
    var resolveCount = 0
    var resolveFailedCount = 0
    var updateCount = 0
    var closeTapCount = 0
    var resolvedProvider: PromoProvider?
    var updatedProvider: PromoProvider?
    var onResolve: ((PromoProvider) -> Void)?
    var onResolveFailure: (() -> Void)?

    override init() {
        super.init()
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

    func promoViewProviderDidTapCloseButton(_ promoView: PromoView) {
        closeTapCount += 1
    }
}
