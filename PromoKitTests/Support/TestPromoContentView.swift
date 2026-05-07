import UIKit
@testable import PromoKit

/// Bare-bones content view used by the test providers' content-view dequeue path.
final class TestPromoContentView: PromoContentView {
    required init(promoView: PromoView) {
        super.init(promoView: promoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
