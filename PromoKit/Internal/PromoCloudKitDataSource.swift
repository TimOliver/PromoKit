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
        Self.fetchAllPages(startingAt: nil as CKQueryOperation.Cursor?, fetchPage: { cursor, receiveRecord, finishPage in
            let operation = cursor.map { CKQueryOperation(cursor: $0) } ?? CKQueryOperation(query: query)
            operation.desiredKeys = desiredKeys
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result { receiveRecord(record) }
            }
            operation.queryResultBlock = finishPage
            self.database.add(operation)
        }, recordHandler: recordHandler, completion: completion)
    }

    /// The cursor is opaque; keeping page traversal independent of its representation
    /// lets tests exercise continuation and error handling without a live database.
    static func fetchAllPages<Cursor>(
        startingAt cursor: Cursor?,
        fetchPage: @escaping (Cursor?, @escaping (CKRecord) -> Void,
                              @escaping (Result<Cursor?, Error>) -> Void) -> Void,
        recordHandler: @escaping (CKRecord) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        fetchPage(cursor, recordHandler) { result in
            switch result {
            case .success(let nextCursor?):
                fetchAllPages(startingAt: nextCursor, fetchPage: fetchPage,
                              recordHandler: recordHandler, completion: completion)
            case .success(nil):
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    func fetchRecord(withID recordID: CKRecord.ID,
                     completion: @escaping (CKRecord?, Error?) -> Void) {
        database.fetch(withRecordID: recordID, completionHandler: completion)
    }
}
