import XCTest
@testable import PromoKit

@MainActor
final class PromoCacheTests: XCTestCase {

    func testCacheRoundTripsStringDateAndClearsAllValuesAcrossInstances() {
        let cache = PromoCache()
        let otherCache = PromoCache()
        let owner = NSObject()
        let namespace = UUID().uuidString
        defer { cache.clearValues(forObject: owner, objectType: namespace) }
        let date = Date(timeIntervalSinceReferenceDate: 600_000)

        cache.setString("hello", forKey: "greeting", fromObject: owner, objectType: namespace)
        cache.setDate(date, forKey: "stamp", fromObject: owner, objectType: namespace)

        XCTAssertEqual(otherCache.string(forKey: "greeting", fromObject: owner, objectType: namespace), "hello")
        XCTAssertEqual(otherCache.date(forKey: "stamp", fromObject: owner, objectType: namespace), date)
        XCTAssertNil(otherCache.string(forKey: "missing", fromObject: owner, objectType: namespace),
                     "Unset keys should read back as nil")

        otherCache.clearValues(forObject: owner, objectType: namespace)
        XCTAssertNil(cache.string(forKey: "greeting", fromObject: owner, objectType: namespace))
        XCTAssertNil(cache.date(forKey: "stamp", fromObject: owner, objectType: namespace))
    }

    func testConcurrentCacheWritesPreserveAllIndependentKeysAcrossInstances() {
        let cache = PromoCache()
        let owner = NSObject()
        let namespace = UUID().uuidString
        defer { cache.clearValues(forObject: owner, objectType: namespace) }
        let workerCount = 8
        let writesPerWorker = 64

        // Each worker models a separate provider and cache instance. Independent
        // keys in their shared namespace must not overwrite each other's updates.
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let workerCache = PromoCache()
            let workerOwner = NSObject()
            for index in 0..<writesPerWorker {
                let key = "worker-\(worker)-record-\(index)"
                workerCache.setString(key, forKey: key, fromObject: workerOwner, objectType: namespace)
            }
        }

        let defaultsKey = cache.userDefaultsKey(fromObject: owner, objectType: namespace)
        let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
        XCTAssertEqual(stored.count, workerCount * writesPerWorker,
                       "Independent concurrent writes lost \(workerCount * writesPerWorker - stored.count) cache entries")
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
