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
///         heading         (String)         - The main title shown at the top in bold text
///         byline          (String)         - Additional auxillary text shown in a smaller font below the heading. (Optional)
///         thumbnail       (Data)           - An image that may be shown alongside the heading and byline.
///         url             (String)         - A url that will open when the user taps the view.
///         postDate        (Date, Sortable) - The date that this event was posted. The latest one will always be fetched.
///         expiration      (Date)           - A date denoting when this event should stop being shown.
///         localDuration   (Int)            - Once downloaded, the number of hours this event should be cached and shown to users.
///         maxVersion      (String)         - The highest version that this app needs to be at to be shown.
///         minVersion      (String)         - Alternatively, the minimum version the app needs to be for this to be shown.
///

@objc(PMKCloudEventProvider)
public class PromoCloudEventProvider: NSObject, PromoProvider {
    public func fetchNewContent(for promoView: PromoView, 
                                with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        resultHandler(.contentAvailable)
    }
    
    public func contentView(for promoView: PromoView) -> PromoContentView {
        promoView.dequeueContentView(for: PromoContainerContentView.self)
    }
}
