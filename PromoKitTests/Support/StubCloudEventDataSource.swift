import Foundation
import CloudKit
@testable import PromoKit

/// `PromoCloudEventDataSource` stub that vends canned records and errors to exercise
/// `PromoCloudEventProvider`'s fetch logic without touching CloudKit.
final class StubCloudEventDataSource: PromoCloudEventDataSource {
    var callbackQueue = DispatchQueue.main
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
        // Tests can select a background queue, matching CloudKit callback delivery.
        callbackQueue.async {
            for record in self.queryRecords { recordHandler(record) }
            completion(self.queryError)
        }
    }

    func fetchRecord(withID recordID: CKRecord.ID,
                     completion: @escaping (CKRecord?, Error?) -> Void) {
        fetchCallCount += 1
        callbackQueue.async {
            completion(self.fetchRecord, self.fetchError)
        }
    }
}
