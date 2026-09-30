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
        expired["expirationDate"] = Date.distantPast as NSDate
        let nonExpiring = CKRecord(recordType: "PromoEvent")
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
        let cacheURL = PromoCache().fileURL(forKey: recordName, fromObject: provider)
        try? FileManager.default.removeItem(at: cacheURL)
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
