//
//  PromoCloudEventProvider.swift
//
//  Copyright 2024 Timothy Oliver. All rights reserved.
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

/// A provider that checks for certain records in this app's public CloudKit database,
/// and displays the first valid entry found in a table list style content view.
/// This is useful for broadcasting new time-limited announcements about the app to users.
///
/// This provider expects a specific record type to be configured inside this app's CloudKit instance.
/// The record's parameters are:
///
/// Name:   
///         PromoEvent
/// Schema:
///         recordName       (Ref)    - (Queryable) The CloudKit metadata name for this record. Can be used to uniquely identify this record.
///         createdTimestamp (Date)   - (Sortable) The CloudKit metadata creation date for this record. Can be used to sort events.
///         heading          (String) - The main title shown at the top in bold text.
///         byline           (String) - Additional auxillary text shown in a smaller font below the heading. (Optional)
///         thumbnail        (Data)   - An image that may be shown alongside the heading and byline. (Optional)
///         url              (String) - A url that will open when the user taps the view. (Optional)
///         expirationDate   (Date)   - (Sortable, Queryable) A date denoting when this event should stop being shown. (Optional)
///         localDuration    (Int)    - Once downloaded, the number of hours this event should be cached and shown to users. (Optional)
///         maxVersion       (String) - The highest version that this app needs to be at to be shown. (Optional)
///         minVersion       (String) - Alternatively, the minimum version the app needs to be for this to be shown. (Optional)
///

@objc(PMKCloudEventProvider)
public class PromoCloudEventProvider: NSObject, PromoProvider {

    // Constant CloudKit names
    private struct Constants {
        static let recordType = "PromoEvent"
        static let headingKey = "heading"
        static let bylineKey = "byline"
    }

    // The container that will be queried. Default value is this app's default container
    private let containerIdentifier: String?

    // Fetches the public database for the initial container
    private lazy var publicDatabase: CKDatabase = {
        if let containerIdentifier { return CKContainer(identifier: containerIdentifier).publicCloudDatabase }
        return CKContainer.default().publicCloudDatabase
    }()

    // The maximum size this provider should be
    private let maximumSize: CGSize = CGSize(width: 450, height: 75)

    // Retain the result handler until we've downloaded all the data
    public var resultHandler: PromoProviderContentFetchHandler?

    // The ID of the record we queried
    public var recordName: String?

    // If found, the record to show
    private var record: CKRecord?

    // MARK: - Init

    /// Create a new instance of this provider with the specified CloudKit container name
    /// - Parameter containerIdentifier: The container name to use (eg iCloud.dev.tim.promokit). Specify nil for the app's default container
    init(containerIdentifier: String? = nil) {
        self.containerIdentifier = containerIdentifier
    }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping PromoProviderContentFetchHandler) {
        self.resultHandler = resultHandler
        fetchLatestEventRecord()
    }
    
    public func contentView(for promoView: PromoView) -> PromoContentView {
        let contentView = promoView.dequeueContentView(for: PromoTableListContentView.self)
        if let heading = record?[Constants.headingKey] as? String, let byline = record?[Constants.bylineKey] as? String {
            contentView.configure(title: heading, detailText: byline)
        }
        return contentView
    }

    public func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        CGSize(width: min(maximumSize.width, fittingSize.width),
               height: min(maximumSize.height, fittingSize.height))
    }

    // MARK: - Private

    private func fetchLatestEventRecord() {
        // Create the query, searching for the first item that hasn't expired yet
        let predicate = NSPredicate(format: "expirationDate > now()")
        let query = CKQuery(recordType: Constants.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "expirationDate", ascending: true)]

        // Create the query operation
        let queryOperation = CKQueryOperation(query: query)
        queryOperation.resultsLimit = 1
        queryOperation.desiredKeys = ["recordName"]
        queryOperation.recordFetchedBlock = { [weak self] record in
            // Skip downloading the data again if we've already downloaded it
            guard record.recordID.recordName != self?.recordName else { return }
            self?.fetchEventRecordWithID(record.recordID)
        }
        publicDatabase.add(queryOperation)
    }

    private func fetchEventRecordWithID(_ recordID: CKRecord.ID) {
        publicDatabase.fetch(withRecordID: recordID) { record, error in
            guard record != nil, error == nil else {
                self.resultHandler?(.fetchRequestFailed)
                return
            }
            self.record = record
            self.recordName = record?.recordID.recordName
            self.resultHandler?(.contentAvailable)
        }
    }
}
