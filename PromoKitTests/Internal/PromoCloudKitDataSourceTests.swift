import XCTest
import CloudKit
@testable import PromoKit

@MainActor
final class PromoCloudKitDataSourceTests: XCTestCase {

    func testCloudKitDataSourceInitDefaultsToTheDefaultContainer() {
        // Passing nil should fall through to CKContainer.default() — no exception, no crash,
        // and the data source ends up holding the default public database.
        let dataSource = PromoCloudKitDataSource(containerIdentifier: nil)
        XCTAssertNotNil(dataSource)
    }

    func testCloudKitDataSourceInitAcceptsExplicitContainerIdentifier() {
        // The non-nil branch wraps CKContainer(identifier:) — not a network call, just
        // wires up the database reference. Asserts the initializer accepts an identifier
        // without crashing.
        let dataSource = PromoCloudKitDataSource(containerIdentifier: "iCloud.dev.tim.promokit.tests")
        XCTAssertNotNil(dataSource)
    }

    func testCloudKitDataSourceFetchRecordDispatchesWithoutCrashing() {
        // We can't drive the CloudKit response without hitting the network, but the wrapper
        // method itself runs synchronously: it constructs a CKDatabase fetch and returns. We
        // only need to know the call site doesn't crash on dispatch — the completion block
        // is captured by CKDatabase and may fire later (or not) without affecting the test.
        let dataSource = PromoCloudKitDataSource(containerIdentifier: "iCloud.dev.tim.promokit.tests")
        dataSource.fetchRecord(withID: CKRecord.ID(recordName: "missing")) { _, _ in }
    }
}

extension PromoCloudKitDataSourceTests {
    func testQueryTraversesEveryPageBeforeCompleting() {
        var pages: [Int] = []
        var records: [String] = []
        var completionCount = 0
        PromoCloudKitDataSource.fetchAllPages(startingAt: nil as Int?, fetchPage: { cursor, receive, finish in
            let page = cursor ?? 0
            pages.append(page)
            XCTAssertEqual(completionCount, 0)
            receive(CKRecord(recordType: "PromoEvent", recordID: CKRecord.ID(recordName: "page-\(page)")))
            finish(.success(page < 2 ? page + 1 : nil))
        }, recordHandler: { records.append($0.recordID.recordName) }, completion: { error in
            XCTAssertNil(error)
            completionCount += 1
        })
        XCTAssertEqual(pages, [0, 1, 2])
        XCTAssertEqual(records, ["page-0", "page-1", "page-2"])
        XCTAssertEqual(completionCount, 1)
    }

    func testQueryPropagatesContinuationFailureExactlyOnce() {
        var pages: [Int] = []
        var completionCount = 0
        PromoCloudKitDataSource.fetchAllPages(startingAt: nil as Int?, fetchPage: { cursor, _, finish in
            let page = cursor ?? 0
            pages.append(page)
            if page == 0 { finish(.success(1)) }
            else { finish(.failure(NSError(domain: "CloudPagination", code: 42))) }
        }, recordHandler: { _ in XCTFail("No records supplied") }, completion: { error in
            XCTAssertEqual((error as NSError?)?.code, 42)
            completionCount += 1
        })
        XCTAssertEqual(pages, [0, 1])
        XCTAssertEqual(completionCount, 1)
    }
}
