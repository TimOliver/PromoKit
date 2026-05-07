import Foundation
import CloudKit
@testable import PromoKit

/// `PromoCloudEventDataSource` stub that vends canned records and errors to exercise
/// `PromoCloudEventProvider`'s fetch logic without touching CloudKit.
final class StubCloudEventDataSource: PromoCloudEventDataSource {
    var queryRecords: [CKRecord] = []
    var queryError: Error?
    var fetchRecord: CKRecord?
    var fetchError: Error?
    private(set) var queryCallCount = 0
    private(set) var fetchCallCount = 0
    private(set) var lastQuery: CKQuery?

    func performQuery(_ query: CKQuery,
                      desiredKeys: [String],
                      recordHandler: @escaping (CKRecord) -> Void,
                      completion: @escaping (Error?) -> Void) {
        queryCallCount += 1
        lastQuery = query
        // Hop to the main queue to mirror the real CKDatabase behaviour where callbacks
        // arrive asynchronously — provider code should remain correct under that ordering.
        DispatchQueue.main.async {
            for record in self.queryRecords { recordHandler(record) }
            completion(self.queryError)
        }
    }

    func fetchRecord(withID recordID: CKRecord.ID,
                     completion: @escaping (CKRecord?, Error?) -> Void) {
        fetchCallCount += 1
        DispatchQueue.main.async {
            completion(self.fetchRecord, self.fetchError)
        }
    }
}
