import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoContainerContentViewTests: XCTestCase {

    func testContainerContentViewPrepareForReuseRemovesAllSubviews() {
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let contentView = PromoContainerContentView(promoView: promoView)
        contentView.addSubview(UIView())
        contentView.addSubview(UIView())
        XCTAssertEqual(contentView.subviews.count, 2)

        contentView.prepareForReuse()
        XCTAssertEqual(contentView.subviews.count, 0)
    }
}
