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
}
