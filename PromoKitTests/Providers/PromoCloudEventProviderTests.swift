import XCTest
import UIKit
import CloudKit
@testable import PromoKit

@MainActor
final class PromoCloudEventProviderTests: XCTestCase {

    func testCloudEventVersionEligibilityUsesInclusiveBounds() {
        XCTAssertTrue(PromoCloudEventProvider.isVersionEligible("2.0.0",
                                                                minVersion: "1.0.0",
                                                                maxVersion: "2.0.0"))
        XCTAssertTrue(PromoCloudEventProvider.isVersionEligible("2.0.0",
                                                                minVersion: "2.0.0",
                                                                maxVersion: "3.0.0"))
        XCTAssertFalse(PromoCloudEventProvider.isVersionEligible("1.9.9", minVersion: "2.0.0"))
        XCTAssertFalse(PromoCloudEventProvider.isVersionEligible("3.0.1", maxVersion: "3.0.0"))
        XCTAssertTrue(PromoCloudEventProvider.isVersionEligible(" 2.10 ",
                                                                minVersion: " 2.9 ",
                                                                maxVersion: "\n2.10\n"))
        XCTAssertTrue(PromoCloudEventProvider.isVersionEligible("", minVersion: "9.9.9", maxVersion: "0.0.1"))
        XCTAssertTrue(PromoCloudEventProvider.isVersionEligible("2.0.0", minVersion: " ", maxVersion: "\n"))
    }

    func testCloudEventQueryPredicateAllowsRecordsWithoutExpirationDate() {
        // Asserting on the predicate's behavior rather than its `predicateFormat` string —
        // NSPredicate normalizes the format differently across iOS versions (NULL → nil,
        // for example), so format matching becomes brittle without adding any safety.
        let predicate = PromoCloudEventProvider.eventQueryPredicate(eventType: "app-update")

        let recordWithoutExpiry: NSDictionary = ["type": "app-update"]
        let recordWithFutureExpiry: NSDictionary = [
            "type": "app-update",
            "expirationDate": Date().addingTimeInterval(60)
        ]
        let recordWithPastExpiry: NSDictionary = [
            "type": "app-update",
            "expirationDate": Date().addingTimeInterval(-60)
        ]
        let recordWithMismatchedType: NSDictionary = ["type": "other"]

        XCTAssertTrue(predicate.evaluate(with: recordWithoutExpiry),
                      "Records without an expirationDate should remain eligible")
        XCTAssertTrue(predicate.evaluate(with: recordWithFutureExpiry),
                      "Records with a future expirationDate should be eligible")
        XCTAssertFalse(predicate.evaluate(with: recordWithPastExpiry),
                       "Records past their expirationDate should be filtered out")
        XCTAssertFalse(predicate.evaluate(with: recordWithMismatchedType),
                       "Records of a different type should be filtered out")
    }

    func testCloudEventRecordPreferencePrefersExpiringRecords() {
        let expiringRecord = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "expiring"))
        expiringRecord["expirationDate"] = Date().addingTimeInterval(60) as NSDate

        let nonExpiringRecord = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "non-expiring"))

        XCTAssertTrue(PromoCloudEventProvider.isRecordPreferred(expiringRecord, over: nonExpiringRecord))
        XCTAssertFalse(PromoCloudEventProvider.isRecordPreferred(nonExpiringRecord, over: expiringRecord))

        let laterExpiringRecord = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "later"))
        laterExpiringRecord["expirationDate"] = Date().addingTimeInterval(120) as NSDate

        XCTAssertTrue(PromoCloudEventProvider.isRecordPreferred(expiringRecord, over: laterExpiringRecord))
        XCTAssertFalse(PromoCloudEventProvider.isRecordPreferred(laterExpiringRecord, over: expiringRecord))

        let alphabeticallyFirst = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "a"))
        let alphabeticallySecond = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "b"))

        XCTAssertTrue(PromoCloudEventProvider.isRecordPreferred(alphabeticallyFirst, over: alphabeticallySecond))
        XCTAssertFalse(PromoCloudEventProvider.isRecordPreferred(alphabeticallySecond, over: alphabeticallyFirst))
    }

    func testCloudEventReplaceCachedFileOverwritesAndRemovesOldData() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let cacheURL = temporaryDirectory.appendingPathComponent("thumbnail.cache")
        let sourceURL = temporaryDirectory.appendingPathComponent("thumbnail.new")
        try Data("old".utf8).write(to: cacheURL)
        try Data("new".utf8).write(to: sourceURL)

        PromoCloudEventProvider.replaceCachedFile(at: cacheURL, with: sourceURL)
        XCTAssertEqual(try String(contentsOf: cacheURL), "new")

        PromoCloudEventProvider.replaceCachedFile(at: cacheURL, with: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testCloudEventProviderResolvesContentWhenDataSourceVendsRecord() {
        let dataSource = StubCloudEventDataSource()
        let record = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "now"))
        record["title"] = "Welcome"
        dataSource.queryRecords = [record]
        dataSource.fetchRecord = record

        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        let result = waitForFetch(provider: provider, promoView: promoView)
        XCTAssertEqual(result, .contentAvailable)
        XCTAssertEqual(dataSource.queryCallCount, 1)
        XCTAssertEqual(dataSource.fetchCallCount, 1)
    }

    func testCloudEventContentViewConfiguresTableListContent() throws {
        let dataSource = StubCloudEventDataSource()
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let queryRecord = CKRecord(recordType: "PromoEvent", recordID: recordID)
        queryRecord["title"] = "Launch"
        let fullRecord = CKRecord(recordType: "PromoEvent", recordID: recordID)
        fullRecord["title"] = "Launch"
        fullRecord["subtitle"] = "New features are ready"
        fullRecord["url"] = "https://example.com/news"
        fullRecord["thumbnail"] = CKAsset(fileURL: try temporaryPNGURL(color: .orange))
        dataSource.queryRecords = [queryRecord]
        dataSource.fetchRecord = fullRecord

        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        defer { removeCachedFile(for: recordID.recordName, provider: provider) }
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .contentAvailable)

        let contentView = provider.contentView(for: promoView)
        guard let tableListContentView = contentView as? PromoTableListContentView else {
            return XCTFail("Cloud events should render through PromoTableListContentView")
        }

        XCTAssertEqual(tableListContentView.label.attributedText?.string,
                       "Launch\nNew features are ready")
        XCTAssertEqual(tableListContentView.footnoteLabel.text, "example.com")
        XCTAssertFalse(tableListContentView.imageView.isHidden)
        XCTAssertNotNil(tableListContentView.imageView.image)
    }

    func testCloudEventContentViewStaysEmptyWithoutTitle() {
        let dataSource = StubCloudEventDataSource()
        let record = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: UUID().uuidString))
        dataSource.queryRecords = [record]
        dataSource.fetchRecord = record

        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .contentAvailable)

        let contentView = provider.contentView(for: promoView)
        guard let tableListContentView = contentView as? PromoTableListContentView else {
            return XCTFail("Cloud events should render through PromoTableListContentView")
        }

        XCTAssertNil(tableListContentView.label.attributedText)
        XCTAssertNil(tableListContentView.footnoteLabel.text)
        XCTAssertTrue(tableListContentView.imageView.isHidden)
    }

    func testCloudEventProviderUsesQueriedRecordWhenFullFetchFails() {
        let dataSource = StubCloudEventDataSource()
        let record = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: UUID().uuidString))
        record["title"] = "Cached announcement"
        dataSource.queryRecords = [record]
        dataSource.fetchError = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)

        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        defer { removeCachedFile(for: record.recordID.recordName, provider: provider) }
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .contentAvailable)
        XCTAssertEqual(dataSource.fetchCallCount, 1)

        let contentView = provider.contentView(for: promoView)
        let tableListContentView = try? XCTUnwrap(contentView as? PromoTableListContentView)
        XCTAssertEqual(tableListContentView?.label.attributedText?.string, "Cached announcement")
    }

    func testCloudEventLocalDurationCachesFirstAccessDate() {
        let dataSource = StubCloudEventDataSource()
        let recordName = UUID().uuidString
        let record = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: recordName))
        record["title"] = "Short lived"
        record["localDuration"] = NSNumber(value: 1)
        dataSource.queryRecords = [record]
        dataSource.fetchRecord = record

        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        let cache = PromoCache()
        cache.clearValues(forObject: provider)
        defer { cache.clearValues(forObject: provider) }
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .contentAvailable)
        XCTAssertNotNil(cache.date(forKey: recordName, fromObject: provider))
        XCTAssertEqual(dataSource.fetchCallCount, 1)
    }

    func testCloudEventLocalDurationRejectsExpiredCachedRecord() {
        let dataSource = StubCloudEventDataSource()
        let recordName = UUID().uuidString
        let record = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: recordName))
        record["title"] = "Expired locally"
        record["localDuration"] = NSNumber(value: 1)
        dataSource.queryRecords = [record]

        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        let cache = PromoCache()
        cache.clearValues(forObject: provider)
        cache.setDate(Date().addingTimeInterval(-2 * 60 * 60), forKey: recordName, fromObject: provider)
        defer { cache.clearValues(forObject: provider) }
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .noContentAvailable)
        XCTAssertEqual(dataSource.fetchCallCount, 0)
    }

    func testCloudEventProviderReportsNoContentWhenDataSourceReturnsNoRecords() {
        let dataSource = StubCloudEventDataSource()
        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        let result = waitForFetch(provider: provider, promoView: promoView)
        XCTAssertEqual(result, .noContentAvailable)
        XCTAssertEqual(dataSource.queryCallCount, 1)
        XCTAssertEqual(dataSource.fetchCallCount, 0,
                       "Without a candidate record, the provider must not request the full fetch")
    }

    func testCloudEventProviderReportsFailureWhenQueryErrors() {
        let dataSource = StubCloudEventDataSource()
        dataSource.queryError = NSError(domain: CKErrorDomain, code: CKError.networkUnavailable.rawValue)
        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        let result = waitForFetch(provider: provider, promoView: promoView)
        XCTAssertEqual(result, .fetchRequestFailed)
    }

    func testCloudEventProviderForwardsRecordTypeAndEventTypeToQuery() {
        let dataSource = StubCloudEventDataSource()
        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: "app-update",
                                               dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        _ = waitForFetch(provider: provider, promoView: promoView)

        // CKQuery disables local predicate evaluation, so we inspect the query's wiring
        // (recordType + type-filter clause in the predicate format) rather than running it.
        // Predicate evaluation correctness is covered by `testCloudEventQueryPredicate…`.
        guard let query = dataSource.lastQuery else {
            return XCTFail("Provider should have issued a query through the data source")
        }
        XCTAssertEqual(query.recordType, "PromoEvent")
        XCTAssertTrue(query.predicate.predicateFormat.contains("\"app-update\""),
                      "Predicate should constrain results to the configured eventType")
    }

    // MARK: - Helpers

    private func waitForFetch(provider: PromoProvider,
                              promoView: PromoView,
                              timeout: TimeInterval = 1.0) -> PromoProviderFetchContentResult {
        let completed = expectation(description: "Provider fetch completes")
        var captured: PromoProviderFetchContentResult?
        provider.fetchNewContent(for: promoView) { result in
            captured = result
            completed.fulfill()
        }
        wait(for: [completed], timeout: timeout)
        return captured ?? .fetchRequestFailed
    }

    private func temporaryPNGURL(color: UIColor) throws -> URL {
        let image = makePromoTestImage(size: CGSize(width: 8, height: 8), color: color)
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        return url
    }

    private func removeCachedFile(for recordName: String, provider: PromoCloudEventProvider) {
        let cacheURL = PromoCache().fileURL(forKey: recordName, fromObject: provider)
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
