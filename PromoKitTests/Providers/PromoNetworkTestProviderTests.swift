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

    func testNetworkTestProviderFetchReportsContentAvailableAfterDelay() {
        // The provider exists to *simulate* a slow network — assert it actually delivers
        // its result on the main queue rather than completing synchronously.
        let provider = PromoNetworkTestProvider()
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        let completed = expectation(description: "Network test provider completes")

        var captured: PromoProviderFetchContentResult?
        var completedOnMain = false
        provider.fetchNewContent(for: promoView) { result in
            captured = result
            completedOnMain = Thread.isMainThread
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5.0)
        XCTAssertEqual(captured, .contentAvailable)
        XCTAssertTrue(completedOnMain,
                      "fetchNewContent uses DispatchQueue.main.asyncAfter — handler must land on main")
    }
}
