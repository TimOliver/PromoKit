import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoContentViewTests: XCTestCase {

    func testContentViewWantsSizingControlDefaultsToFalseAndExposesPromoView() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let contentView = PromoContentView(promoView: promoView)

        XCTAssertFalse(contentView.wantsSizingControl)
        XCTAssertTrue(contentView.promoView === promoView)
    }
}
