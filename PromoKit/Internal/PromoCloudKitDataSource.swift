//
//  PromoCloudKitDataSource.swift
//
//  Copyright 2024-2025 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import CloudKit

/// Default `PromoCloudEventDataSource` backed by a real `CKDatabase`.
internal final class PromoCloudKitDataSource: PromoCloudEventDataSource {
    private let database: CKDatabase

    init(containerIdentifier: String?) {
        if let containerIdentifier {
            self.database = CKContainer(identifier: containerIdentifier).publicCloudDatabase
        } else {
            self.database = CKContainer.default().publicCloudDatabase
        }
    }

    func performQuery(_ query: CKQuery,
                      desiredKeys: [String],
                      recordHandler: @escaping (CKRecord) -> Void,
                      completion: @escaping (Error?) -> Void) {
        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = desiredKeys

        // A per-record failure is skipped rather than surfaced, matching the old
        // recordFetchedBlock, which simply never fired for a record it couldn't decode.
        // Anything fatal to the query still arrives through the result block below.
        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result { recordHandler(record) }
        }
        operation.queryResultBlock = { result in
            switch result {
            case .success: completion(nil)
            case .failure(let error): completion(error)
            }
        }
        database.add(operation)
    }

    func fetchRecord(withID recordID: CKRecord.ID,
                     completion: @escaping (CKRecord?, Error?) -> Void) {
        database.fetch(withRecordID: recordID, completionHandler: completion)
    }
}
