import XCTest
@testable import PromoKit

@MainActor
final class PromoCacheTests: XCTestCase {

    func testCacheRoundTripsStringDateAndClearsAllValues() {
        let cache = PromoCache()
        let owner = NSObject()
        defer { cache.clearValues(forObject: owner) }
        let date = Date(timeIntervalSinceReferenceDate: 600_000)

        cache.setString("hello", forKey: "greeting", fromObject: owner)
        cache.setDate(date, forKey: "stamp", fromObject: owner)

        XCTAssertEqual(cache.string(forKey: "greeting", fromObject: owner), "hello")
        XCTAssertEqual(cache.date(forKey: "stamp", fromObject: owner), date)
        XCTAssertNil(cache.string(forKey: "missing", fromObject: owner),
                     "Unset keys should read back as nil")

        cache.clearValues(forObject: owner)
        XCTAssertNil(cache.string(forKey: "greeting", fromObject: owner))
        XCTAssertNil(cache.date(forKey: "stamp", fromObject: owner))
    }

    func testCacheFileDataRoundTripsThroughTemporaryDirectory() throws {
        let cache = PromoCache()
        let owner = NSObject()
        let key = UUID().uuidString
        let payload = Data("test content".utf8)

        XCTAssertNil(cache.fileData(forKey: key, fromObject: owner),
                     "Reading a file that hasn't been written should return nil")

        try cache.setFileData(payload, forKey: key, fromObject: owner)
        XCTAssertEqual(cache.fileData(forKey: key, fromObject: owner), payload)

        // Cleanup so reruns don't leak temp files.
        try? FileManager.default.removeItem(at: cache.fileURL(forKey: key, fromObject: owner))
    }
}
