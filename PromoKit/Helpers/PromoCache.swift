//
//  PromoProviderCoordinator.swift
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

/// A very basic caching mechanism that allows providers to store basic key-value
/// data in user defaults, and file data to the app's tmp directory.
public class PromoCache {

    // MARK: - File Management

    /// If available, loads the data from disk for a previously cached file.
    /// - Parameters:
    ///   - key: The unique key identifying this file
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    /// - Returns: The data if available or nil otherwise
    public func fileData(forKey key: String, fromObject object: AnyObject) -> Data? {
        try? Data(contentsOf: fileURL(forKey: key, fromObject: object), options: [.mappedIfSafe])
    }

    /// Saves the provided data to the app tmp directory
    /// - Parameters:
    ///   - data: The data to persist to disk
    ///   - key: The unique key to identify this file
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    public func setFileData(_ data: Data, forKey key: String, fromObject object: AnyObject) throws {
        try data.write(to: fileURL(forKey: key, fromObject: object))
    }

    // MARK: - User Defaults

    /// Saves a string value to user defaults against the hosting object
    /// - Parameters:
    ///   - string: The value to save
    ///   - key: A unique identifier to retrieve this value
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    public func setString(_ string: String?, forKey key: String, fromObject object: AnyObject, objectType: String? = nil) {
        setValue(string, forKey: key, fromObject: object, objectType: objectType)
    }

    /// Fetches a previously saved string value from user defaults
    /// - Parameters:
    ///   - key: The unique identifier to retrieve this value
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    public func string(forKey key: String, fromObject object: AnyObject, objectType: String? = nil) -> String? {
        return value(forKey: key, fromObject: object, objectType: objectType) as? String
    }

    /// Saves a date value to user defaults against the hosting object
    /// - Parameters:
    ///   - date: The date to save
    ///   - key: A unique identifier to retrieve this value
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    public func setDate(_ date: Date?, forKey key: String, fromObject object: AnyObject, objectType: String? = nil) {
        setValue(date, forKey: key, fromObject: object, objectType: objectType)
    }

    /// Fetches a previously saved date value from user defaults
    /// - Parameters:
    ///   - key: The unique identifier to retrieve this value
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    public func date(forKey key: String, fromObject object: AnyObject, objectType: String? = nil) -> Date? {
        return value(forKey: key, fromObject: object, objectType: objectType) as? Date
    }

    /// Saves a data value to user defaults associated with the calling object
    /// - Parameters:
    ///   - value: The value to be saved to user defaults
    ///   - key: A unique value that the hosting object can use to identify this data
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    public func setValue(_ value: Any?, forKey key: String, fromObject object: AnyObject, objectType: String? = nil) {
        let userDefaultsKey = userDefaultsKey(fromObject: object, objectType: objectType)
        var settings = UserDefaults.standard.dictionary(forKey: userDefaultsKey) ?? [String: String]()
        settings[key] = value
        UserDefaults.standard.set(settings, forKey: userDefaultsKey)
    }

    /// Retrives a data value from user defaults associated with the hosting object
    /// - Parameters:
    ///   - key: A unique value that the hosting object can use to identify this data
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    /// - Returns: The value if any, or nil otherwise
    public func value(forKey key: String, fromObject object: AnyObject, objectType: String? = nil) -> Any? {
        let userDefaultsKey = userDefaultsKey(fromObject: object, objectType: objectType)
        guard let settings = UserDefaults.standard.dictionary(forKey: userDefaultsKey) else { return nil }
        return settings[key]
    }

    /// Deletes all cached data for an associated object
    /// - Parameters:
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    public func clearValues(forObject object: AnyObject, objectType: String? = nil) {
        let userDefaultsKey = userDefaultsKey(fromObject: object, objectType: objectType)
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Cached Item Managemment

    /// Generates a unique identifier that will be used as the top level key for a single provider in user defaults
    /// - Parameters:
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    ///   - objectType: An additional optional string to identify unique copies of the hosting object
    /// - Returns: The formatted key
    public func userDefaultsKey(fromObject object: AnyObject, objectType: String? = nil) -> String {
        "PromoKit.\(String(describing: type(of: object)))" + (objectType != nil ? ".\(objectType!)" : "")
    }

    /// Generates a file path for the provided unique identifiers in the app's temp directory
    /// - Parameters:
    ///   - key: The unique key for this item
    ///   - object: The hosting object (eg a provider) that is responsible for this data
    /// - Returns: The absolute URL to the file
    public func fileURL(forKey key: String, fromObject object: AnyObject) -> URL {
        let fileName = "PromoKit.\(String(describing: type(of: object))).\(key)"
        return URL(fileURLWithPath: NSTemporaryDirectory().appending(fileName))
    }
}
