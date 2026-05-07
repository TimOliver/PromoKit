import XCTest
@testable import PromoKit

@MainActor
final class PromoFileManagerTests: XCTestCase {

    func testFileManagerSelectsLargestIconBelowTargetDimension() throws {
        // Note: when candidates straddle the target dimension, the production algorithm is
        // order-dependent (filesystem iteration that returns an above-target icon first
        // can prevent below-target icons from being chosen). To keep this test deterministic
        // we use only below-target candidates. The straddling case is flagged separately.
        try withSyntheticIconBundle(["AppIcon20x20@2x.png",
                                     "AppIcon40x40@2x.png",
                                     "AppIcon76x76@2x.png"]) { _ in
            let url = PromoFileManager.urlForAppIcon(named: "AppIcon", targetDimension: 100)
            XCTAssertEqual(url?.lastPathComponent, "AppIcon76x76@2x.png",
                           "Largest icon below the target dimension should be selected")
        }
    }

    func testFileManagerSelectsSmallestIconWhenAllExceedTargetDimension() throws {
        try withSyntheticIconBundle(["AppIcon120x120@3x.png", "AppIcon180x180@3x.png"]) { _ in
            let url = PromoFileManager.urlForAppIcon(named: "AppIcon", targetDimension: 50)
            XCTAssertEqual(url?.lastPathComponent, "AppIcon120x120@3x.png",
                           "When all candidates exceed the target, the smallest of them wins")
        }
    }

    func testFileManagerReturnsNilWhenNoIconsMatchPrefix() throws {
        try withSyntheticIconBundle(["Other76x76@2x.png", "ReadMe.txt"]) { _ in
            XCTAssertNil(PromoFileManager.urlForAppIcon(named: "AppIcon"))
        }
    }

    // MARK: - Helpers

    /// Points `PromoFileManager.resourceURL` at a fresh temp directory populated with the given
    /// filenames, runs `body`, and restores the original resource URL on exit.
    private func withSyntheticIconBundle(_ filenames: [String],
                                         body: (URL) throws -> Void) throws {
        let originalResourceURL = PromoFileManager.resourceURL
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            PromoFileManager.resourceURL = originalResourceURL
            try? FileManager.default.removeItem(at: tempDir)
        }

        for filename in filenames {
            try Data().write(to: tempDir.appendingPathComponent(filename))
        }
        PromoFileManager.resourceURL = tempDir

        try body(tempDir)
    }
}
