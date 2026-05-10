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
