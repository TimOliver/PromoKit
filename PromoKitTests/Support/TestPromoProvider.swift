import Foundation
import UIKit
@testable import PromoKit

/// A configurable provider used across tests to drive the resolution pipeline through
/// every relevant outcome (content available, no content, fetch failure, slow completion,
/// never-completing). Mirrors a small fraction of the real provider surface — only the
/// fields the existing test suite needs.
final class TestPromoProvider: NSObject, PromoProvider {
    let result: PromoProviderFetchContentResult
    let isInternetAccessRequired: Bool
    let isOfflineCacheAvailable: Bool
    let showsLoadingIndicatorDuringFetch: Bool
    let needsReloadOnSizeChange: Bool
    let fetchRefreshInterval: TimeInterval
    let completionDelay: TimeInterval
    let completes: Bool

    var fetchCount = 0
    var onFetch: (() -> Void)?
    private(set) weak var lastPromoView: PromoView?
    private(set) var didMoveToPromoViewCount = 0

    init(result: PromoProviderFetchContentResult,
         isInternetAccessRequired: Bool = false,
         isOfflineCacheAvailable: Bool = false,
         showsLoadingIndicatorDuringFetch: Bool = false,
         needsReloadOnSizeChange: Bool = false,
         fetchRefreshInterval: TimeInterval = 0,
         completionDelay: TimeInterval = 0,
         completes: Bool = true) {
        self.result = result
        self.isInternetAccessRequired = isInternetAccessRequired
        self.isOfflineCacheAvailable = isOfflineCacheAvailable
        self.showsLoadingIndicatorDuringFetch = showsLoadingIndicatorDuringFetch
        self.needsReloadOnSizeChange = needsReloadOnSizeChange
        self.fetchRefreshInterval = fetchRefreshInterval
        self.completionDelay = completionDelay
        self.completes = completes
    }

    func didMoveToPromoView(_ promoView: PromoView) {
        lastPromoView = promoView
        didMoveToPromoViewCount += 1
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
