import XCTest
import UIKit
@testable import PromoKit

@MainActor
final class PromoAppRaterProviderTests: XCTestCase {

    func testAppRaterPreferredContentSizeClampsToProviderMaximum() {
        let provider = PromoAppRaterProvider()
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 600, height: 200))

        // Larger fitting size — provider clamps to its 450 x 75 maximum.
        let clamped = provider.preferredContentSize(fittingSize: CGSize(width: 600, height: 200),
                                                    for: promoView)
        XCTAssertEqual(clamped, CGSize(width: 450, height: 75))

        // Smaller fitting size — fitting size wins on each axis independently.
        let constrained = provider.preferredContentSize(fittingSize: CGSize(width: 320, height: 50),
                                                        for: promoView)
        XCTAssertEqual(constrained, CGSize(width: 320, height: 50))
    }

    func testAppRaterContentViewIsConfiguredTableListContentView() {
        let provider = PromoAppRaterProvider()
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 75))

        let contentView = provider.contentView(for: promoView)
        XCTAssertTrue(contentView is PromoTableListContentView,
                      "AppRater provider should hand back a table-list style content view")
    }

    func testAppRaterCornerRadiusScalesWithViewHeight() {
        let provider = PromoAppRaterProvider()
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))

        let radius = provider.cornerRadius(for: promoView, with: .zero)
        XCTAssertEqual(radius, 30, accuracy: 0.0001,
                       "Corner radius should be 30% of the promo view's height")
    }

    func testAppRaterFetchNewContentReportsAvailableWhenIconCannotBeFound() throws {
        // Point the file manager at an empty directory so urlForAppIcon returns nil and the
        // background block hits its fallback "no decode" branch — the provider still reports
        // content available because the rater UI degrades to text-only.
        let originalResourceURL = PromoFileManager.resourceURL
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            PromoFileManager.resourceURL = originalResourceURL
            try? FileManager.default.removeItem(at: tempDir)
        }
        PromoFileManager.resourceURL = tempDir

        let provider = PromoAppRaterProvider(appIconName: "DefinitelyMissing")
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 75))
        let completed = expectation(description: "Fallback resultHandler is invoked")

        provider.fetchNewContent(for: promoView) { result in
            XCTAssertEqual(result, .contentAvailable)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2.0)

        XCTAssertNil(storedAppIcon(in: provider),
                     "No icon should be cached when no matching file was found")
    }

    func testAppRaterFetchNewContentDecodesAndStoresIcon() throws {
        // Drop a single synthetic AppIcon into a temp resource directory and verify the
        // provider walks the full happy path: locating the file, decoding it, then caching
        // the resized image so contentView(for:) can hand it to the table-list view.
        let originalResourceURL = PromoFileManager.resourceURL
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            PromoFileManager.resourceURL = originalResourceURL
            try? FileManager.default.removeItem(at: tempDir)
        }

        let icon = makePromoTestImage(size: CGSize(width: 76, height: 76), color: .green)
        let pngData = try XCTUnwrap(icon.pngData())
        let iconURL = tempDir.appendingPathComponent("AppIcon76x76@2x.png")
        try pngData.write(to: iconURL)
        PromoFileManager.resourceURL = tempDir

        // Note: the file manager's selection algorithm uses strict < / > comparisons,
        // so we ask for a slightly larger target dimension than the icon on disk to ensure
        // the 76x76 candidate is selected via the "largest below target" branch.
        let provider = PromoAppRaterProvider(appIconName: "AppIcon", maxIconDimension: 80)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 320, height: 75))
        let completed = expectation(description: "Decoded icon is published back on the main queue")

        provider.fetchNewContent(for: promoView) { result in
            XCTAssertEqual(result, .contentAvailable)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5.0)

        XCTAssertNotNil(storedAppIcon(in: provider),
                        "Decoded icon should be retained for reuse in the content view")
    }

    // MARK: - Helpers

    /// Reads the private `appIcon` slot via Mirror — the provider doesn't expose it but
    /// we still want to verify it was populated after a successful decode.
    private func storedAppIcon(in provider: PromoAppRaterProvider) -> UIImage? {
        for child in Mirror(reflecting: provider).children {
            if child.label == "appIcon" { return child.value as? UIImage }
        }
        return nil
    }
}
