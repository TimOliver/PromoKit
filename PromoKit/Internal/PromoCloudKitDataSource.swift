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
        operation.recordFetchedBlock = { record in recordHandler(record) }
        operation.queryCompletionBlock = { _, error in completion(error) }
        database.add(operation)
    }

    func fetchRecord(withID recordID: CKRecord.ID,
                     completion: @escaping (CKRecord?, Error?) -> Void) {
        database.fetch(withRecordID: recordID, completionHandler: completion)
    }
}
