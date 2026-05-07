import UIKit
@testable import PromoKit

/// A provider that always reports a fixed `preferredContentSize`, used to verify
/// `PromoView.sizeThatFits(_:providerClass:)` routes sizing requests to the named provider.
final class FixedSizePromoProvider: NSObject, PromoProvider {
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    func fetchNewContent(for promoView: PromoView,
                         with resultHandler: @escaping PromoProviderContentFetchHandler) {
        resultHandler(.contentAvailable)
    }

    func contentView(for promoView: PromoView) -> PromoContentView {
        promoView.dequeueContentView(for: TestPromoContentView.self)
    }

    func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        CGSize(width: width, height: height)
    }
}
