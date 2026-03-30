//
//  PromoCloudEventProvider.swift
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
///         type             (String) - (Queryable) A generic field that can categorize types of events so they can be filtered (ie "app-update" vs "ad")
///         expirationDate   (Date)   - (Sortable, Queryable) A date denoting when this event should stop being shown. (Optional. If omitted, the event is treated as non-expiring and lower priority than expiring events.)
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
        static let expirationDate = "expirationDate"
    }

    // The CloudKit record type name that this provider queries (eg "PromoEvent")
    private let recordType: String

    // The identifier of the CloudKit container to query, or nil to use the app's default container
    private let containerIdentifier: String?

    // An optional string to narrow the query to a specific event category within the record type
    private let eventType: String?

    // Fetches the public database for the initial container
    private lazy var publicDatabase: CKDatabase = {
        if let containerIdentifier { return CKContainer(identifier: containerIdentifier).publicCloudDatabase }
        return CKContainer.default().publicCloudDatabase
    }()

    // A cache for persisting record access dates and thumbnail images between sessions
    private let cache = PromoCache()

    // The maximum display size for this provider's content view
    private let maximumSize: CGSize = CGSize(width: 450, height: 75)

    // The result handler captured at the start of a fetch and called when the fetch resolves
    private var resultHandler: PromoProviderContentFetchHandler?

    // Incremented on each new fetch to invalidate callbacks from previous in-flight requests
    private var fetchToken: UUID?

    // The CloudKit record selected for display after a successful query
    private var record: CKRecord?

    // The decoded thumbnail image for the current record, loaded from cache or downloaded
    private var thumbnail: UIImage?

    // MARK: - Init

    /// Create a new instance of this provider with the specified CloudKit container name
    /// - Parameter containerIdentifier: The container name to use (eg iCloud.dev.tim.promokit). Specify nil for the app's default container
    /// - Parameter eventType: An optional type to filter for (eg, app-specific announcements vs global announcements)
    public init(recordType: String = "PromoEvent", containerIdentifier: String? = nil, eventType: String? = nil) {
        self.recordType = recordType
        self.containerIdentifier = containerIdentifier
        self.eventType = eventType
    }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping PromoProviderContentFetchHandler) {
        self.resultHandler = resultHandler
        record = nil
        thumbnail = nil
        fetchToken = UUID()
        fetchLatestEventRecordID()
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

    /// Performs a CloudKit query to find the most recently expiring valid event record.
    /// Fetches only the lightweight metadata fields needed for eligibility checking.
    private func fetchLatestEventRecordID() {
        // Capture the token for this fetch so callbacks from a previous fetch are ignored
        let token = fetchToken

        // Create the query, searching for records that either haven't expired yet, or never expire.
        let predicate = Self.eventQueryPredicate(eventType: eventType)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Constants.expirationDate, ascending: true)]

        // Create the query operation, fetching just the data we need to check its validity
        let queryOperation = CKQueryOperation(query: query)
        queryOperation.desiredKeys = desiredKeys()
        queryOperation.recordFetchedBlock = { [weak self] record in
            guard self?.fetchToken == token else { return }
            self?.didFetchRecordForQuery(record)
        }
        queryOperation.queryCompletionBlock = { [weak self] _, error in
            guard self?.fetchToken == token else { return }
            self?.recordQueryDidComplete(error: error, token: token)
        }
        publicDatabase.add(queryOperation)
    }

    /// Called when the CloudKit query has successfully fetched a record
    /// - Parameter record: The record that was fetched
    private func didFetchRecordForQuery(_ record: CKRecord) {
        guard isRecordEligibleForDisplay(record) else { return }
        guard Self.isRecordPreferred(record, over: self.record) else { return }
        self.record = record
    }

    /// Examines the provided record to see if it's still valid to display
    /// - Parameter record: The record to display
    /// - Returns: Whether the object is eligible or not
    private func isRecordEligibleForDisplay(_ record: CKRecord) -> Bool {
        guard isCurrentAppVersionEligible(for: record) else { return false }

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

        // Compare the current date to the adjusted expiry date
        let referenceDate = Date().timeIntervalSinceReferenceDate
        let localExpirationReferenceDate = firstAccessDate
            .addingTimeInterval(TimeInterval(localDuration * 60 * 60))
            .timeIntervalSinceReferenceDate

        return referenceDate < localExpirationReferenceDate
    }

    /// Returns whether the current app version satisfies the min/max version constraints stored in the record.
    private func isCurrentAppVersionEligible(for record: CKRecord) -> Bool {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
        guard let currentVersion else { return true }

        let minVersion = record[Constants.minVersion] as? String
        let maxVersion = record[Constants.maxVersion] as? String
        return Self.isVersionEligible(currentVersion, minVersion: minVersion, maxVersion: maxVersion)
    }

    static func isVersionEligible(_ currentVersion: String,
                                  minVersion: String? = nil,
                                  maxVersion: String? = nil) -> Bool {
        let currentVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentVersion.isEmpty else { return true }

        let minVersion = minVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let minVersion, !minVersion.isEmpty,
           currentVersion.compare(minVersion, options: .numeric) == .orderedAscending {
            return false
        }

        let maxVersion = maxVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let maxVersion, !maxVersion.isEmpty,
           currentVersion.compare(maxVersion, options: .numeric) == .orderedDescending {
            return false
        }

        return true
    }

    /// Called when the CloudKit record query operation completes.
    /// - Parameters:
    ///   - error: An error, if any occurred during the query.
    ///   - token: The fetch token captured at query start, used to detect stale completions.
    private func recordQueryDidComplete(error: Error?, token: UUID?) {
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
            prepareRecordForDisplay(record, token: token)
            return
        }

        // Otherwise, we can terminate out here.
        // CloudKit blocks are called in the background, so we have to manually go back to the main thread
        handleResult(result)
    }

    /// Before displaying the record, fetch the full record so the latest thumbnail state is always reflected.
    /// - Parameters:
    ///   - record: The record to display.
    ///   - token: The fetch token captured at query start, used to detect stale completions.
    private func prepareRecordForDisplay(_ record: CKRecord, token: UUID?) {
        // Re-fetch the selected record so thumbnail changes on the server are reflected locally.
        publicDatabase.fetch(withRecordID: record.recordID) { [weak self] record, error in
            guard self?.fetchToken == token else { return }
            guard let self else { return }

            guard let record, error == nil else {
                if let record = self.record {
                    self.loadThumbnailFromCache(record: record)
                }
                self.handleResult(.contentAvailable)
                return
            }

            self.record = record
            self.saveThumbnailToCache(record: record)
            self.loadThumbnailFromCache(record: record)
            self.handleResult(.contentAvailable)
        }
    }

    /// Moves the downloaded thumbnail asset from CloudKit's temporary location into the app's cache directory.
    /// Any existing cached asset for this record is replaced, and removed if the record no longer has a thumbnail.
    private func saveThumbnailToCache(record: CKRecord) {
        let cacheURL = cache.fileURL(forKey: record.recordID.recordName, fromObject: self)
        let thumbnailAsset = record[Constants.thumbnail] as? CKAsset
        let thumbnailURL = thumbnailAsset?.fileURL
        Self.replaceCachedFile(at: cacheURL, with: thumbnailURL)
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
        guard let handler = resultHandler else { return }
        resultHandler = nil
        DispatchQueue.main.async {
            handler(result)
        }
    }

    /// Specifies all of the keys we want to have downloaded from CloudKit, excluding the thumbnail
    /// - Returns: An array of all of the desired keys to download
    private func desiredKeys() -> [String] {
        return ["recordName",
                Constants.title,
                Constants.subtitle,
                Constants.url,
                Constants.expirationDate,
                Constants.localDuration,
                Constants.minVersion,
                Constants.maxVersion]
    }
}

extension PromoCloudEventProvider {

    static func eventQueryPredicate(eventType: String?) -> NSPredicate {
        var predicates = [NSPredicate(format: "\(Constants.expirationDate) > now() OR \(Constants.expirationDate) == NULL")]
        if let eventType, !eventType.isEmpty {
            predicates.append(NSPredicate(format: "type == %@", eventType))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func isRecordPreferred(_ record: CKRecord, over currentRecord: CKRecord?) -> Bool {
        guard let currentRecord else { return true }

        let recordExpirationDate = record[Constants.expirationDate] as? Date
        let currentExpirationDate = currentRecord[Constants.expirationDate] as? Date
        switch (recordExpirationDate, currentExpirationDate) {
        case let (recordExpirationDate?, currentExpirationDate?):
            if recordExpirationDate != currentExpirationDate {
                return recordExpirationDate < currentExpirationDate
            }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        let recordCreationDate = record.creationDate ?? .distantPast
        let currentCreationDate = currentRecord.creationDate ?? .distantPast
        if recordCreationDate != currentCreationDate {
            return recordCreationDate > currentCreationDate
        }

        return record.recordID.recordName < currentRecord.recordID.recordName
    }

    static func replaceCachedFile(at cacheURL: URL, with sourceURL: URL?) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.removeItem(at: cacheURL)
        }

        guard let sourceURL else { return }
        try? fileManager.moveItem(at: sourceURL, to: cacheURL)
    }
}
