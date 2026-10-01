import XCTest
import UIKit
import CloudKit
@testable import PromoKit

private final class HeldLifecycleCloudDataSource: PromoCloudEventDataSource {
    let containerIdentifier: String? = "iCloud.dev.tim.promokit.lifecycle-tests"
    var onFetch: (() -> Void)?
    private var queryRecordHandler: ((CKRecord) -> Void)?
    private var queryCompletion: ((Error?) -> Void)?
    private var fetchCompletion: ((CKRecord?, Error?) -> Void)?

    func performQuery(_ query: CKQuery, desiredKeys: [String],
                      recordHandler: @escaping (CKRecord) -> Void,
                      completion: @escaping (Error?) -> Void) {
        queryRecordHandler = recordHandler
        queryCompletion = completion
    }

    func fetchRecord(withID recordID: CKRecord.ID,
                     completion: @escaping (CKRecord?, Error?) -> Void) {
        fetchCompletion = completion
        onFetch?()
    }

    func completeQuery(with record: CKRecord) {
        queryRecordHandler?(record)
        queryCompletion?(nil)
        queryRecordHandler = nil
        queryCompletion = nil
    }

    func completeFetch(with record: CKRecord) {
        fetchCompletion?(record, nil)
        fetchCompletion = nil
    }
}

extension PromoCloudEventProviderTests {
    func testPendingCloudQueryDoesNotRetainProviderOrHost() {
        let source = HeldLifecycleCloudDataSource()
        weak var releasedProvider: PromoCloudEventProvider?
        weak var releasedView: PromoView?
        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "Abandoned query"
        var fetchStarted = false
        source.onFetch = { fetchStarted = true }

        autoreleasepool {
            let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
            let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
            releasedProvider = provider
            releasedView = view
            provider.fetchNewContent(for: view) { _ in XCTFail("A released provider must not deliver query results") }
        }

        XCTAssertNil(releasedProvider)
        XCTAssertNil(releasedView)
        source.completeQuery(with: record)
        drainLifecycleCloudCallbacks()
        XCTAssertFalse(fetchStarted, "A late query must not start a full-record fetch after teardown")
    }

    func testPendingCloudRecordFetchDoesNotRetainProviderOrHost() {
        let source = HeldLifecycleCloudDataSource()
        weak var releasedProvider: PromoCloudEventProvider?
        weak var releasedView: PromoView?
        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "Abandoned fetch"
        let started = expectation(description: "Full-record fetch is held")
        source.onFetch = { started.fulfill() }

        autoreleasepool {
            let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
            let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
            releasedProvider = provider
            releasedView = view
            provider.fetchNewContent(for: view) { _ in XCTFail("A released provider must not deliver record results") }
            source.completeQuery(with: record)
            wait(for: [started], timeout: 1)
            _ = provider.currentRecordName // Wait for the state queue to leave the fetch hook before teardown.
        }

        XCTAssertNil(releasedProvider)
        XCTAssertNil(releasedView)
        source.completeFetch(with: record)
        drainLifecycleCloudCallbacks()
    }

    private func drainLifecycleCloudCallbacks() {
        let drained = expectation(description: "Late CloudKit callbacks drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

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

    func testCloudEventQueryPredicateFiltersOnlyEventTypeWithSupportedOperators() {
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

        for eventType in [nil, "", "app-update"] {
            let predicate = PromoCloudEventProvider.eventQueryPredicate(eventType: eventType)
            XCTAssertFalse(predicate.predicateFormat.contains(" OR "),
                           "CloudKit rejects OR even though NSPredicate can evaluate it locally")
            XCTAssertTrue(predicate.evaluate(with: recordWithoutExpiry))
            XCTAssertTrue(predicate.evaluate(with: recordWithFutureExpiry))
            XCTAssertTrue(predicate.evaluate(with: recordWithPastExpiry),
                          "Expiration is filtered by the provider after fetching metadata")
            XCTAssertEqual(predicate.evaluate(with: recordWithMismatchedType), eventType != "app-update")
        }
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
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

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

    func testCloudEventProviderRejectsExpiredQueryRecords() {
        let dataSource = StubCloudEventDataSource()
        let expired = CKRecord(recordType: "PromoEvent")
        expired["title"] = "Expired announcement"
        expired["expirationDate"] = Date.distantPast as NSDate
        dataSource.queryRecords = [expired]
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .noContentAvailable)
        XCTAssertEqual(dataSource.fetchCallCount, 0, "Expired records must not trigger an asset download")
        XCTAssertNil(provider.currentRecordName)
    }

    func testCloudEventProviderPrefersSoonestValidExpiryAmongQueryRecords() {
        let dataSource = StubCloudEventDataSource()
        let expired = CKRecord(recordType: "PromoEvent")
        expired["expirationDate"] = Date.distantPast as NSDate
        let nonExpiring = CKRecord(recordType: "PromoEvent")
        let later = CKRecord(recordType: "PromoEvent")
        later["expirationDate"] = Date().addingTimeInterval(7_200) as NSDate
        let sooner = CKRecord(recordType: "PromoEvent")
        sooner["title"] = "Current announcement"
        sooner["expirationDate"] = Date().addingTimeInterval(3_600) as NSDate
        dataSource.queryRecords = [later, expired, nonExpiring, sooner]
        dataSource.fetchRecord = sooner
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .contentAvailable)
        XCTAssertEqual(dataSource.lastFetchedRecordID, sooner.recordID)
        XCTAssertEqual(provider.currentRecordName, sooner.recordID.recordName)
    }

    func testCloudEventProviderSelectsNonExpiringRecordWhenOthersHaveExpired() {
        let dataSource = StubCloudEventDataSource()
        let expired = CKRecord(recordType: "PromoEvent")
        expired["type"] = "app-update"
        expired["expirationDate"] = Date.distantPast as NSDate
        let nonExpiring = CKRecord(recordType: "PromoEvent")
        nonExpiring["type"] = "app-update"
        nonExpiring["title"] = "Ongoing announcement"
        dataSource.queryRecords = [expired, nonExpiring]
        dataSource.fetchRecord = nonExpiring
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: "app-update", dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .contentAvailable)
        XCTAssertEqual(dataSource.lastFetchedRecordID, nonExpiring.recordID)
        XCTAssertEqual(provider.currentRecordName, nonExpiring.recordID.recordName)
    }

    func testCloudEventProviderRechecksExpirationAfterFullFetch() {
        let dataSource = StubCloudEventDataSource()
        let queryRecord = CKRecord(recordType: "PromoEvent")
        queryRecord["title"] = "Announcement"
        queryRecord["expirationDate"] = Date().addingTimeInterval(3_600) as NSDate
        let fullRecord = CKRecord(recordType: "PromoEvent", recordID: queryRecord.recordID)
        fullRecord["title"] = "Withdrawn announcement"
        fullRecord["expirationDate"] = Date.distantPast as NSDate
        dataSource.queryRecords = [queryRecord]
        dataSource.fetchRecord = fullRecord
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: dataSource)
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: promoView), .noContentAvailable)
        XCTAssertEqual(dataSource.fetchCallCount, 1)
        XCTAssertNil(provider.currentRecordName)
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
        XCTAssertNotNil(cache.date(forKey: provider.cacheKey(for: record.recordID), fromObject: provider))
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
        cache.setDate(Date().addingTimeInterval(-2 * 60 * 60),
                      forKey: provider.cacheKey(for: record.recordID), fromObject: provider)
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

    func testCloudEventProviderSkipsHiddenRecordNamesAndPicksNext() {
        let dataSource = StubCloudEventDataSource()

        let hidden = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "hidden-notice"))
        hidden["title"] = "Hidden"
        let visible = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "visible-notice"))
        visible["title"] = "Visible"

        dataSource.queryRecords = [hidden, visible]
        dataSource.fetchRecord = visible

        let provider = PromoCloudEventProvider(recordType: "PromoEvent",
                                               eventType: nil,
                                               dataSource: dataSource)
        provider.setHiddenRecordNames(["hidden-notice"])
        let promoView = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        let result = waitForFetch(provider: provider, promoView: promoView)
        XCTAssertEqual(result, .contentAvailable)
        XCTAssertEqual(provider.currentRecordName, "visible-notice",
                       "A hidden record must be skipped in favour of the next eligible one")
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
        let key = provider.cacheKey(for: CKRecord.ID(recordName: recordName))
        let cacheURL = PromoCache().fileURL(forKey: key, fromObject: provider)
        try? FileManager.default.removeItem(at: cacheURL)
    }
}

extension PromoCloudEventProviderTests {
    func testFailedThumbnailReplacementKeepsLastGoodImageUntilExplicitRemoval() throws {
        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "Announcement"
        let originalURL = try temporaryPNGURL(color: .orange)
        let originalImage = try XCTUnwrap(UIImage(contentsOfFile: originalURL.path)?.pngData())
        record["thumbnail"] = CKAsset(fileURL: originalURL)
        let source = StubCloudEventDataSource()
        source.queryRecords = [record]
        source.fetchRecord = record
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let missingReplacementURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let replacementURL = try temporaryPNGURL(color: .blue)
        let replacementImage = try XCTUnwrap(UIImage(contentsOfFile: replacementURL.path)?.pngData())
        defer {
            removeCachedFile(for: record.recordID.recordName, provider: provider)
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: replacementURL)
        }

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        let initialContent = try XCTUnwrap(provider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(initialContent.imageView.image?.pngData(), originalImage)

        record["thumbnail"] = CKAsset(fileURL: missingReplacementURL)
        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        let contentAfterFailure = try XCTUnwrap(provider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(contentAfterFailure.imageView.image?.pngData(), originalImage,
                       "An unavailable replacement asset must not destroy the last successfully cached image")

        record["thumbnail"] = CKAsset(fileURL: replacementURL)
        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        let replacementContent = try XCTUnwrap(provider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(replacementContent.imageView.image?.pngData(), replacementImage)

        record["thumbnail"] = nil
        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        let contentAfterRemoval = try XCTUnwrap(provider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertNil(contentAfterRemoval.imageView.image)
        XCTAssertTrue(contentAfterRemoval.imageView.isHidden)
        let cacheURL = PromoCache().fileURL(forKey: provider.cacheKey(for: record.recordID), fromObject: provider)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testCachedFileReplacementFailurePreservesExistingFileAndSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("thumbnail.cache")
        let unreadableSource = directory.appendingPathComponent("directory-instead-of-image")
        try FileManager.default.createDirectory(at: unreadableSource, withIntermediateDirectories: false)
        try Data("existing".utf8).write(to: cacheURL)

        PromoCloudEventProvider.replaceCachedFile(at: cacheURL, with: unreadableSource)

        XCTAssertEqual(try Data(contentsOf: cacheURL), Data("existing".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreadableSource.path))

        PromoCloudEventProvider.replaceCachedFile(at: cacheURL, with: cacheURL)
        XCTAssertEqual(try Data(contentsOf: cacheURL), Data("existing".utf8),
                       "Using the existing cache file as the source must not delete it")
    }
}

extension PromoCloudEventProviderTests {
    func testBackgroundCloudCallbacksResolveOnMainThread() {
        let source = StubCloudEventDataSource()
        source.callbackQueue = DispatchQueue(label: "PromoKitTests.CloudCallbacks")
        let record = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "background-notice"))
        record["title"] = "Background notice"
        source.queryRecords = [record]
        source.fetchRecord = record
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let done = expectation(description: "Background callbacks resolve")
        provider.fetchNewContent(for: view) { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result, .contentAvailable)
            XCTAssertEqual(provider.currentRecordName, "background-notice")
            done.fulfill()
        }
        // Exercise host state access while background callbacks are arriving.
        for _ in 0..<100 {
            provider.setHiddenRecordNames(["unrelated-notice"])
            XCTAssertEqual(provider.hiddenRecordNames, ["unrelated-notice"])
            _ = provider.currentRecordName
        }
        wait(for: [done], timeout: 2)
    }
}

extension PromoCloudEventProviderTests {
    func testDisplayedNoticeIdentitySurvivesReplacementFetch() {
        let source = StubCloudEventDataSource()
        let first = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "displayed-notice"))
        first["title"] = "Displayed notice"
        source.queryRecords = [first]
        source.fetchRecord = first
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        _ = provider.contentView(for: view)
        let next = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "replacement-notice"))
        next["title"] = "Replacement"
        source.queryRecords = [next]
        source.fetchRecord = next
        let resolved = expectation(description: "Replacement resolves")
        provider.fetchNewContent(for: view) { result in
            XCTAssertEqual(result, .contentAvailable)
            resolved.fulfill()
        }
        XCTAssertEqual(provider.currentRecordName, "displayed-notice")
        wait(for: [resolved], timeout: 1)
        XCTAssertEqual(provider.currentRecordName, "displayed-notice", "Resolution alone has not replaced the visible content")
        _ = provider.contentView(for: view)
        XCTAssertEqual(provider.currentRecordName, "replacement-notice")
    }
}

extension PromoCloudEventProviderTests {
    func testCloudEventTapOpensDisplayedURL() {
        let source = StubCloudEventDataSource()
        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "Read the announcement"
        record["url"] = "https://example.com/news"
        source.queryRecords = [record]
        source.fetchRecord = record
        var openedURLs: [URL] = []
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil,
                                               dataSource: source, openURL: { openedURLs.append($0) })
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        _ = provider.contentView(for: view)

        let tappingProvider: PromoProvider = provider
        tappingProvider.didTapUpInside?(promoView: view, with: UITouch())

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com/news"])
    }

    func testCloudEventTapIgnoresMissingAndInvalidURLs() {
        let urlStrings: [String?] = [nil, "", "/news", "https://["]
        for urlString in urlStrings {
            let source = StubCloudEventDataSource()
            let record = CKRecord(recordType: "PromoEvent")
            record["title"] = "Announcement"
            record["url"] = urlString
            source.queryRecords = [record]
            source.fetchRecord = record
            var openedURLs: [URL] = []
            let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil,
                                                   dataSource: source, openURL: { openedURLs.append($0) })
            let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
            XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
            _ = provider.contentView(for: view)

            provider.didTapUpInside(promoView: view, with: UITouch())

            XCTAssertTrue(openedURLs.isEmpty)
        }
    }

    func testCloudEventTapKeepsDisplayedDestinationUntilReplacementIsShown() {
        let source = StubCloudEventDataSource()
        let first = CKRecord(recordType: "PromoEvent")
        first["title"] = "Displayed notice"
        first["url"] = "https://example.com/first"
        source.queryRecords = [first]
        source.fetchRecord = first
        var openedURLs: [URL] = []
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil,
                                               dataSource: source, openURL: { openedURLs.append($0) })
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        _ = provider.contentView(for: view)

        let replacement = CKRecord(recordType: "PromoEvent")
        replacement["title"] = "Replacement notice"
        replacement["url"] = "https://example.com/replacement"
        source.queryRecords = [replacement]
        source.fetchRecord = replacement
        let resolved = expectation(description: "Replacement resolves")
        provider.fetchNewContent(for: view) { result in
            XCTAssertEqual(result, .contentAvailable)
            resolved.fulfill()
        }
        provider.didTapUpInside(promoView: view, with: UITouch())
        wait(for: [resolved], timeout: 1)
        provider.didTapUpInside(promoView: view, with: UITouch())
        _ = provider.contentView(for: view)
        provider.didTapUpInside(promoView: view, with: UITouch())

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com/first",
                                                        "https://example.com/first",
                                                        "https://example.com/replacement"])

        let noticeWithoutURL = CKRecord(recordType: "PromoEvent")
        noticeWithoutURL["title"] = "Information only"
        source.queryRecords = [noticeWithoutURL]
        source.fetchRecord = noticeWithoutURL
        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        _ = provider.contentView(for: view)
        provider.didTapUpInside(promoView: view, with: UITouch())
        XCTAssertEqual(openedURLs.count, 3, "Displaying a notice without a URL must clear the previous destination")
    }
}

extension PromoCloudEventProviderTests {
    func testFullRecordVersionChangeCannotBypassEligibility() throws {
        let currentVersion = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String)
        let minimumVersion = currentVersion + ".1"
        XCTAssertFalse(PromoCloudEventProvider.isVersionEligible(currentVersion, minVersion: minimumVersion))
        let source = StubCloudEventDataSource()
        let queryRecord = CKRecord(recordType: "PromoEvent")
        queryRecord["title"] = "Announcement"
        let refreshedRecord = CKRecord(recordType: "PromoEvent", recordID: queryRecord.recordID)
        refreshedRecord["title"] = "Requires a newer app"
        refreshedRecord["minVersion"] = minimumVersion
        source.queryRecords = [queryRecord]
        source.fetchRecord = refreshedRecord
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .noContentAvailable,
                       "The full record is authoritative and no longer eligible for this app version")
        XCTAssertNil(provider.currentRecordName)
    }

    func testFullRecordCategoryChangeCannotBypassEventTypeFilter() {
        let source = StubCloudEventDataSource()
        let queryRecord = CKRecord(recordType: "PromoEvent")
        queryRecord["title"] = "App update"
        queryRecord["type"] = "app-update"
        let refreshedRecord = CKRecord(recordType: "PromoEvent", recordID: queryRecord.recordID)
        refreshedRecord["title"] = "A different category"
        refreshedRecord["type"] = "advertisement"
        source.queryRecords = [queryRecord]
        source.fetchRecord = refreshedRecord
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: "app-update", dataSource: source)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .noContentAvailable,
                       "Stale query matches must not show a refreshed record from another category")
        XCTAssertNil(provider.currentRecordName)
    }

    func testNoticeHiddenDuringFullFetchCannotBecomeAvailable() {
        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "Notice hidden while downloading"
        let source = CloudEventDataSourceWithFetchHook(record: record)
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
        source.beforeFullFetchCompletion = { [weak provider] in
            provider?.setHiddenRecordNames([record.recordID.recordName])
        }
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .noContentAvailable)
        XCTAssertNil(provider.currentRecordName)
    }

    func testCategoryFilteredQueryRequestsCategoryMetadata() {
        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "App update"
        record["type"] = "app-update"
        let source = CloudEventDataSourceWithFetchHook(record: record)
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: "app-update", dataSource: source)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        XCTAssertTrue(source.desiredKeys.contains("type"), "Local filtering requires the category in query metadata")
    }

    func testEligibleRefreshedRecordRemainsAvailableWithOptionalCategoryFilter() throws {
        let currentVersion = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String)
        let eventTypes: [String?] = [nil, "", "app-update", "APP-UPDATE"]
        for eventType in eventTypes {
            let source = StubCloudEventDataSource()
            let queryRecord = CKRecord(recordType: "PromoEvent")
            queryRecord["title"] = "Original title"
            queryRecord["type"] = "app-update"
            let refreshedRecord = CKRecord(recordType: "PromoEvent", recordID: queryRecord.recordID)
            refreshedRecord["title"] = "Updated title"
            refreshedRecord["type"] = "app-update"
            refreshedRecord["minVersion"] = currentVersion
            refreshedRecord["maxVersion"] = currentVersion
            source.queryRecords = [queryRecord]
            source.fetchRecord = refreshedRecord
            let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: eventType, dataSource: source)
            let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

            XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
            let content = try XCTUnwrap(provider.contentView(for: view) as? PromoTableListContentView)
            XCTAssertEqual(content.label.attributedText?.string, "Updated title")
        }
    }
}

private final class CloudEventDataSourceWithFetchHook: PromoCloudEventDataSource {
    let containerIdentifier: String? = "iCloud.dev.tim.promokit.tests"
    let record: CKRecord
    private(set) var desiredKeys: [String] = []
    var beforeFullFetchCompletion: (() -> Void)?

    init(record: CKRecord) { self.record = record }

    func performQuery(_ query: CKQuery, desiredKeys: [String],
                      recordHandler: @escaping (CKRecord) -> Void,
                      completion: @escaping (Error?) -> Void) {
        self.desiredKeys = desiredKeys
        DispatchQueue.main.async {
            recordHandler(self.record)
            completion(nil)
        }
    }

    func fetchRecord(withID recordID: CKRecord.ID, completion: @escaping (CKRecord?, Error?) -> Void) {
        DispatchQueue.main.async {
            self.beforeFullFetchCompletion?()
            completion(self.record, nil)
        }
    }
}

extension PromoCloudEventProviderTests {
    func testServerDeletedNoticeIsNotDisplayedFromQuerySnapshot() {
        let source = StubCloudEventDataSource()
        let queryRecord = CKRecord(recordType: "PromoEvent")
        queryRecord["title"] = "Deleted announcement"
        source.queryRecords = [queryRecord]
        source.fetchError = NSError(domain: CKErrorDomain, code: CKError.unknownItem.rawValue)
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .noContentAvailable,
                       "A permanent missing-record result must not fall back to stale metadata")
        XCTAssertNil(provider.currentRecordName)
    }

    func testTransientFullFetchFailurePreservesQueriedContentAndCachedThumbnail() throws {
        let source = StubCloudEventDataSource()
        let queryRecord = CKRecord(recordType: "PromoEvent")
        queryRecord["title"] = "Current announcement"
        queryRecord["type"] = "app-update"
        source.queryRecords = [queryRecord]
        source.fetchError = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: "app-update", dataSource: source)
        let image = makePromoTestImage(size: CGSize(width: 8, height: 8), color: .orange)
        try PromoCache().setFileData(try XCTUnwrap(image.pngData()),
                                    forKey: provider.cacheKey(for: queryRecord.recordID), fromObject: provider)
        defer { removeCachedFile(for: queryRecord.recordID.recordName, provider: provider) }
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        let content = try XCTUnwrap(provider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(content.label.attributedText?.string, "Current announcement")
        XCTAssertNotNil(content.imageView.image)
        XCTAssertFalse(content.imageView.isHidden)
    }
}

extension PromoCloudEventProviderTests {
    func testContainerCachesKeepAccessDatesAndThumbnailsSeparateAcrossProviderInstances() throws {
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let firstRecord = CKRecord(recordType: "PromoEvent", recordID: recordID)
        firstRecord["title"] = "First container"
        firstRecord["localDuration"] = NSNumber(value: 1)
        let firstImageURL = try temporaryPNGURL(color: .orange)
        let firstImageData = try XCTUnwrap(UIImage(contentsOfFile: firstImageURL.path)?.pngData())
        firstRecord["thumbnail"] = CKAsset(fileURL: firstImageURL)
        let firstSource = StubCloudEventDataSource()
        firstSource.containerIdentifier = "iCloud.tests.first"
        firstSource.queryRecords = [firstRecord]
        firstSource.fetchRecord = firstRecord
        let firstProvider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: firstSource)

        let secondRecord = CKRecord(recordType: "PromoEvent", recordID: recordID)
        secondRecord["title"] = "Second container"
        secondRecord["localDuration"] = NSNumber(value: 1)
        let secondImageURL = try temporaryPNGURL(color: .blue)
        let secondImageData = try XCTUnwrap(UIImage(contentsOfFile: secondImageURL.path)?.pngData())
        secondRecord["thumbnail"] = CKAsset(fileURL: secondImageURL)
        let secondSource = StubCloudEventDataSource()
        secondSource.containerIdentifier = "iCloud.tests.second"
        secondSource.queryRecords = [secondRecord]
        secondSource.fetchError = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)
        let secondProvider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: secondSource)
        let cache = PromoCache()
        let firstKey = firstProvider.cacheKey(for: recordID)
        let secondKey = secondProvider.cacheKey(for: recordID)
        defer {
            cache.setDate(nil, forKey: firstKey, fromObject: firstProvider)
            cache.setDate(nil, forKey: secondKey, fromObject: secondProvider)
            removeCachedFile(for: recordID.recordName, provider: firstProvider)
            removeCachedFile(for: recordID.recordName, provider: secondProvider)
            try? FileManager.default.removeItem(at: firstImageURL)
            try? FileManager.default.removeItem(at: secondImageURL)
        }
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: firstProvider, promoView: view), .contentAvailable)
        let firstAccessDate = try XCTUnwrap(cache.date(forKey: firstKey, fromObject: firstProvider))
        let expiredAccessDate = Date().addingTimeInterval(-2 * 60 * 60)
        cache.setDate(expiredAccessDate, forKey: firstKey, fromObject: firstProvider)

        XCTAssertEqual(waitForFetch(provider: secondProvider, promoView: view), .contentAvailable,
                       "A locally expired record in another container must not suppress this notice")
        let secondContent = try XCTUnwrap(secondProvider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(secondContent.label.attributedText?.string, "Second container")
        XCTAssertNil(secondContent.imageView.image,
                     "A transient asset fetch failure must not borrow the other container's thumbnail")
        let secondAccessDate = try XCTUnwrap(cache.date(forKey: secondKey, fromObject: secondProvider))
        XCTAssertGreaterThan(secondAccessDate, expiredAccessDate)
        XCTAssertEqual(cache.date(forKey: firstKey, fromObject: firstProvider), expiredAccessDate)

        secondSource.fetchError = nil
        secondSource.fetchRecord = secondRecord
        XCTAssertEqual(waitForFetch(provider: secondProvider, promoView: view), .contentAvailable)
        let loadedSecondContent = try XCTUnwrap(secondProvider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(loadedSecondContent.imageView.image?.pngData(), secondImageData)

        firstSource.fetchRecord = nil
        firstSource.fetchError = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)
        let recreatedFirst = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: firstSource)
        XCTAssertEqual(waitForFetch(provider: recreatedFirst, promoView: view), .noContentAvailable,
                       "Recreating a provider must preserve its container's local expiry")
        cache.setDate(firstAccessDate, forKey: firstKey, fromObject: firstProvider)
        XCTAssertEqual(waitForFetch(provider: recreatedFirst, promoView: view), .contentAvailable)
        let restoredFirstContent = try XCTUnwrap(recreatedFirst.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(restoredFirstContent.imageView.image?.pngData(), firstImageData,
                       "Saving the second container's image must not overwrite the first")

        secondSource.fetchRecord = nil
        secondSource.fetchError = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)
        let recreatedSecond = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: secondSource)
        XCTAssertEqual(waitForFetch(provider: recreatedSecond, promoView: view), .contentAvailable)
        let restoredSecondContent = try XCTUnwrap(recreatedSecond.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(restoredSecondContent.imageView.image?.pngData(), secondImageData)
        XCTAssertEqual(cache.date(forKey: secondKey, fromObject: recreatedSecond), secondAccessDate)
    }

    func testDefaultAndExplicitContainerIdentitySharePersistentRecordCache() throws {
        let defaultDataSource = PromoCloudKitDataSource(containerIdentifier: nil)
        let resolvedIdentifier = try XCTUnwrap(defaultDataSource.containerIdentifier)
        let explicitDataSource = PromoCloudKitDataSource(containerIdentifier: resolvedIdentifier)
        XCTAssertEqual(explicitDataSource.containerIdentifier, defaultDataSource.containerIdentifier)

        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "Default container notice"
        record["localDuration"] = NSNumber(value: 1)
        let imageURL = try temporaryPNGURL(color: .green)
        let imageData = try XCTUnwrap(UIImage(contentsOfFile: imageURL.path)?.pngData())
        record["thumbnail"] = CKAsset(fileURL: imageURL)
        let initialSource = StubCloudEventDataSource()
        initialSource.containerIdentifier = defaultDataSource.containerIdentifier
        initialSource.queryRecords = [record]
        initialSource.fetchRecord = record
        let initialProvider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: initialSource)
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let cache = PromoCache()
        let key = initialProvider.cacheKey(for: record.recordID)
        defer {
            cache.setDate(nil, forKey: key, fromObject: initialProvider)
            removeCachedFile(for: record.recordID.recordName, provider: initialProvider)
            try? FileManager.default.removeItem(at: imageURL)
        }
        XCTAssertEqual(waitForFetch(provider: initialProvider, promoView: view), .contentAvailable)
        let accessDate = try XCTUnwrap(cache.date(forKey: key, fromObject: initialProvider))

        let restoredSource = StubCloudEventDataSource()
        restoredSource.containerIdentifier = explicitDataSource.containerIdentifier
        restoredSource.queryRecords = [record]
        restoredSource.fetchError = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)
        let restoredProvider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: restoredSource)
        XCTAssertEqual(waitForFetch(provider: restoredProvider, promoView: view), .contentAvailable)
        let content = try XCTUnwrap(restoredProvider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertEqual(content.imageView.image?.pngData(), imageData)
        XCTAssertEqual(cache.date(forKey: restoredProvider.cacheKey(for: record.recordID), fromObject: restoredProvider), accessDate)

        cache.setDate(Date().addingTimeInterval(-2 * 60 * 60), forKey: key, fromObject: restoredProvider)
        let nextProvider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: initialSource)
        XCTAssertEqual(waitForFetch(provider: nextProvider, promoView: view), .noContentAvailable,
                       "Changing between explicit and default container access must not restart the display period")
    }

    func testUnscopedLegacyCacheDoesNotLeakIntoContainerScopedFetch() throws {
        let record = CKRecord(recordType: "PromoEvent")
        record["title"] = "Scoped notice"
        record["localDuration"] = NSNumber(value: 1)
        let source = StubCloudEventDataSource()
        source.queryRecords = [record]
        source.fetchError = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: source)
        let cache = PromoCache()
        let legacyKey = record.recordID.recordName
        let scopedKey = provider.cacheKey(for: record.recordID)
        cache.setDate(.distantPast, forKey: legacyKey, fromObject: provider)
        let image = makePromoTestImage(size: CGSize(width: 8, height: 8), color: .red)
        try cache.setFileData(try XCTUnwrap(image.pngData()), forKey: legacyKey, fromObject: provider)
        defer {
            cache.setDate(nil, forKey: legacyKey, fromObject: provider)
            cache.setDate(nil, forKey: scopedKey, fromObject: provider)
            try? FileManager.default.removeItem(at: cache.fileURL(forKey: legacyKey, fromObject: provider))
        }
        let view = PromoView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))

        XCTAssertEqual(waitForFetch(provider: provider, promoView: view), .contentAvailable)
        let content = try XCTUnwrap(provider.contentView(for: view) as? PromoTableListContentView)
        XCTAssertNil(content.imageView.image, "Legacy data has no trustworthy container identity")
        XCTAssertNotNil(cache.date(forKey: scopedKey, fromObject: provider))
    }
}

extension PromoCloudEventProviderTests {
    func testCloudNoticeUsesItsWidthCapAndAllowsLargerTextToIncreaseHeight() throws {
        let dataSource = StubCloudEventDataSource()
        let record = CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: UUID().uuidString))
        record["title"] = "An important announcement"
        record["subtitle"] = "Please read these details about the latest update to this application."
        dataSource.queryRecords = [record]
        dataSource.fetchRecord = record
        let provider = PromoCloudEventProvider(recordType: "PromoEvent", eventType: nil, dataSource: dataSource)
        let promo = PromoView(frame: CGRect(x: 0, y: 0, width: 500, height: 100))
        XCTAssertEqual(waitForFetch(provider: provider, promoView: promo), .contentAvailable)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 900))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.traitOverrides.preferredContentSizeCategory = .large
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.addSubview(promo)
        let content = try XCTUnwrap(provider.contentView(for: promo) as? PromoTableListContentView)
        promo.addSubview(content)
        window.layoutIfNeeded()
        let normalSize = content.sizeThatFits(CGSize(width: 600, height: 900))
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.layoutIfNeeded()
        let largeSize = content.sizeThatFits(CGSize(width: 600, height: 900))
        XCTAssertTrue(content.wantsSizingControl)
        XCTAssertEqual(largeSize.width, 450)
        XCTAssertGreaterThan(largeSize.height, normalSize.height)
        XCTAssertEqual(dataSource.queryCallCount, 1)
    }
}
