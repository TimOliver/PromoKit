import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoNetworkTestProviderTests: XCTestCase {

    func testNetworkTestProviderConfiguresContentAndSizing() {
        let provider = PromoNetworkTestProvider()
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))

        XCTAssertTrue(provider.isInternetAccessRequired)

        let contentView = provider.contentView(for: promoView)
        XCTAssertTrue(contentView is PromoContainerContentView)

        let size = provider.preferredContentSize(fittingSize: CGSize(width: 300, height: 80),
                                                 for: promoView)
        XCTAssertEqual(size, CGSize(width: 300, height: 30))

        XCTAssertEqual(provider.contentPadding(for: promoView),
                       UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
    }
}
