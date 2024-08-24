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
import UIKit

/// A provider that checks for certain records in this app's public CloudKit database,
/// and displays the first valid entry found in a table list style content view.
/// This is useful for broadcasting new time-limited announcements about the app to users.
///
/// This provider expects a specific record type to be configured inside this app's CloudKit instance.
/// The record's parameters are:
///
/// Name:   
///         PromoEvent       (String) - The default name of the hosting record type. This value may be changed to allow multiple streams of events.
/// Schema:
///         recordName       (Ref)    - (Queryable) The CloudKit metadata name for this record. Can be used to uniquely identify this record.
///         createdTimestamp (Date)   - (Sortable) The CloudKit metadata creation date for this record. Can be used to sort events.
///         title            (String) - The main title shown at the top in bold text.
///         subtitle         (String) - Additional auxillary text shown in a smaller font below the heading. (Optional)
///         thumbnail        (Asset)  - An image that may be shown alongside the heading and byline. (Optional)
///         url              (String) - A url that will open when the user taps the view. (Optional)
///         type             (String) - (Queryable) A type that can be used to filter types of events between different in-app promo views (eg "home", "settings", etc)
///         expirationDate   (Date)   - (Sortable, Queryable) A date denoting when this event should stop being shown. (Optional)
///         localDuration    (Int)    - Once downloaded, the number of hours this event should be cached and shown to users. (Optional)
///         maxVersion       (String) - The highest version that this app needs to be at to be shown. (Optional)
///         minVersion       (String) - Alternatively, the minimum version the app needs to be for this to be shown. (Optional)
///

@objc(PMKPromoCloudEventProvider)
public class PromoCloudEventProvider: NSObject, PromoProvider {

    // Constants for the name of records/properties in CloudKit
    struct Constants {
        // Property names in CloudKit
        static let title = "title"
        static let subtitle = "subtitle"
        static let url = "url"
        static let minVersion = "minVersion"
        static let maxVersion = "maxVersion"
        static let localDuration = "localDuration"
        static let thumbnail = "thumbnail"
    }

    // The record type in CloudKit that stores this data
    private let recordType: String

    // The container that will be queried. Default value is this app's default container
    private let containerIdentifier: String?

    // An optional event type to filter multiple streams of events in the same record type
    private let eventType: String?

    // Fetches the public database for the initial container
    private lazy var publicDatabase: CKDatabase = {
        if let containerIdentifier { return CKContainer(identifier: containerIdentifier).publicCloudDatabase }
        return CKContainer.default().publicCloudDatabase
    }()

    // The parent promo view
    private weak var promoView: PromoView?

    // A cache to store local state about the CloudKit records and
    private let cache = PromoCache()

    // The maximum size this provider should be
    private let maximumSize: CGSize = CGSize(width: 450, height: 75)

    // Retain the result handler until we've downloaded all the data
    public var resultHandler: PromoProviderContentFetchHandler?

    // If found, the record to show
    private var record: CKRecord?

    // If available, the thumbnail image associated with the queried record
    private var thumbnail: UIImage?

    // MARK: - Init

    /// Create a new instance of this provider with the specified CloudKit container name
    /// - Parameter containerIdentifier: The container name to use (eg iCloud.dev.tim.promokit). Specify nil for the app's default container
    init(recordType: String = "PromoEvent", containerIdentifier: String? = nil, eventType: String? = nil) {
        self.recordType = recordType
        self.containerIdentifier = containerIdentifier
        self.eventType = eventType
    }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping PromoProviderContentFetchHandler) {
        self.resultHandler = resultHandler
        self.promoView = promoView
        fetchLatestEventRecordID()
        promoView.setIsLoading(true, animated: true)
    }
    
    public func contentView(for promoView: PromoView) -> PromoContentView {
        let contentView = promoView.dequeueContentView(for: PromoTableListContentView.self)
        var headnote: String?
        if let urlString = record?[Constants.url] as? String, let url = URL(string: urlString) {
            headnote = url.host
        }

        if let heading = record?[Constants.title] as? String {
            let byline = record?[Constants.subtitle] as? String
            contentView.configure(title: heading, detailText: byline, footnote: headnote, image: thumbnail)
        }
        return contentView
    }

    public func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        CGSize(width: min(maximumSize.width, fittingSize.width),
               height: min(maximumSize.height, fittingSize.height))
    }

    // MARK: - Private

    private func fetchLatestEventRecordID() {
        // Create the query, searching for the first item that hasn't expired yet.
        var format = "expirationDate > now()"
        if let eventType { format += " AND type == '\(eventType)'" }
        let predicate = NSPredicate(format: format)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "expirationDate", ascending: true)]

        // Create the query operation, fetching just the data we need to check its validity
        let queryOperation = CKQueryOperation(query: query)
        queryOperation.resultsLimit = 1
        queryOperation.desiredKeys = desiredKeys()
        queryOperation.recordFetchedBlock = { [weak self] record in
            self?.didFetchRecordForQuery(record)
        }
        queryOperation.queryCompletionBlock = { [weak self] _, error in
            self?.recordQueryDidComplete(error: error)
        }
        publicDatabase.add(queryOperation)
    }

    /// Called when the CloudKit query has successfully fetched a record
    /// - Parameter record: The record that was fetched
    private func didFetchRecordForQuery(_ record: CKRecord) {
        guard isRecordEligibleForDisplay(record) else { return }
        self.record = record
    }

    /// Examines the provided record to see if it's still valid to display
    /// - Parameter record: The record to display
    /// - Returns: Whether the object is eligible or not
    private func isRecordEligibleForDisplay(_ record: CKRecord) -> Bool {
        // If we don't have any local duration value, this record is always valid
        guard let localDuration = record[Constants.localDuration] as? Int, localDuration > 0 else {
            return true
        }

        // We track each record via its unique UUID
        let recordName = record.recordID.recordName

        // Check if we've gone past the local display period for this record
        var firstAccessDate = cache.date(forKey: recordName, fromObject: self)
        if firstAccessDate == nil {
            firstAccessDate = Date()
            cache.setDate(firstAccessDate, forKey: recordName, fromObject: self)
        }

        guard let firstAccessDate else { return true }

        // Compare the current date to the adjust expiriy date
        let referenceDate = Date().timeIntervalSinceReferenceDate
        let localExpirationReferenceDate = firstAccessDate
            .addingTimeInterval(TimeInterval(localDuration * 60 * 60))
            .timeIntervalSinceReferenceDate

        return referenceDate < localExpirationReferenceDate
    }

    /// Called when the record query completes.
    /// - Parameter error: An error, if any occurred
    private func recordQueryDidComplete(error: Error?) {
        // Assume the query completed with zero results
        var result: PromoProviderFetchContentResult = .noContentAvailable

        // Errors can occur if CloudKit isn't configured correctly.
        // Expose these errors to the developer so they can fix this.
        if let error {
#if DEBUG
            print("PromoKit.PromoCloudEventProvider: \(error)")
#endif
            result = .fetchRequestFailed
        }

        // If the `recordFetchedBlock` was called and we were able to save a record,
        // lets do one final validation pass to verify the thumbnail.
        if let record = self.record {
            prepareRecordForDisplay(record)
            return
        }

        // Otherwise, we can terminate out here.
        // CloudKit blocks are called in the background, so we have to manually go back to the main thread
        handleResult(result)
    }

    /// Before displaying the record, do a verification pass to determine the state of the thumbnail
    /// - Parameter record: The record to display
    private func prepareRecordForDisplay(_ record: CKRecord) {
        // Load the previously cached thumbnail if we have it
        if loadThumbnailFromCache(record: record) {
            handleResult(.contentAvailable)
            return
        }

        // If we don't have the thumbnail, fetch the entire record from CloudKit
        publicDatabase.fetch(withRecordID: record.recordID) { [weak self] record, error in
            guard let record, error == nil else {
                self?.record = nil
                self?.handleResult(.fetchRequestFailed)
                return
            }

            self?.record = record
            self?.saveThumbnailToCache(record: record)
            self?.loadThumbnailFromCache(record: record)
            self?.handleResult(.contentAvailable)
        }
    }

    private func saveThumbnailToCache(record: CKRecord) {
        guard let thumbnailAsset = record[Constants.thumbnail] as? CKAsset,
              let thumbnailURL = thumbnailAsset.fileURL  else { return }

        let cacheURL = cache.fileURL(forKey: record.recordID.recordName, fromObject: self)
        try? FileManager.default.moveItem(at: thumbnailURL, to: cacheURL)
    }

    /// Loads the thumbnail from the cache.
    /// - Returns: Returns false if no cached thumbnail was found
    @discardableResult private func loadThumbnailFromCache(record: CKRecord) -> Bool {
        // Check to see if we have a cached thumbnail for this record
        let fileURL = cache.fileURL(forKey: record.recordID.recordName, fromObject: self)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            self.thumbnail = UIImage(contentsOfFile: fileURL.path)
        }
        return self.thumbnail != nil
    }

    /// Calls the result handler on the main thread
    /// - Parameter result: The final content discovery result
    private func handleResult(_ result: PromoProviderFetchContentResult) {
        DispatchQueue.main.async { [weak self] in
            self?.promoView?.setIsLoading(false, animated: true)
            self?.resultHandler?(result)
        }
    }

    /// Specifies all of the keys we want to have downloaded from CloudKit, excluding the thumbnail
    /// - Returns: An array of all of the desired keys to download
    private func desiredKeys() -> [String] {
        return ["recordName",
                Constants.title,
                Constants.subtitle,
                Constants.url,
                Constants.localDuration,
                Constants.minVersion,
                Constants.maxVersion]
    }
}
