//
//  PromoAppRaterProvider.swift
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

import UIKit

/// A promo provider that displays a call-to-action to rate this app on the App Store.
/// This can be a great default provider when all other providers are unavailable (such as when offline).
@objc(PMKPromoAppRaterProvider)
public class PromoAppRaterProvider: NSObject, PromoProvider {

    // The name of the app icon in the app bundle
    private var appIconName: String?

    // The icon associated with this app
    private var appIcon: UIImage?

    // The width x height of the app icon
    private var iconDimension: Int

    // The maximum size this provider should be
    private let maximumSize: CGSize = CGSize(width: 450, height: 75)

    /// Creates a new provider with the app's associated app icon
    /// - Parameters:
    ///   - appIconName: The name of the app icon in the asset bundle
    ///   - maxIconDimension: The maximum expected size the icon will be rendered at, in points
    init(appIconName: String = "AppIcon", maxIconDimension: Int = 76) {
        self.appIconName = appIconName
        self.iconDimension = maxIconDimension
    }

    public func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        CGSize(width: min(maximumSize.width, fittingSize.width),
               height: min(maximumSize.height, fittingSize.height))
    }

    public func fetchNewContent(for promoView: PromoView,
                                with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        guard appIconName != nil else {
            resultHandler(.contentAvailable)
            return
        }

        // Perform the decoding and resizing on this promo view's background queue
        let scale = promoView.traitCollection.displayScale
        let operation = BlockOperation()
        operation.addExecutionBlock {
            guard !operation.isCancelled,
                  let appIconName = self.appIconName,
                  let appIconURL = PromoFileManager.urlForAppIcon(named: appIconName, targetDimension: self.iconDimension),
                  let appIcon = UIImage(contentsOfFile: appIconURL.path)
            else {
                OperationQueue.main.addOperation { resultHandler(.contentAvailable) }
                return
            }

            // Decode and resize the image to the desired dimensions.
            let size = CGSize(width: self.iconDimension, height: self.iconDimension)
            let image = PromoImageProcessing.decodedImage(appIcon, fittingSize: size, scale: scale)

            OperationQueue.main.addOperation {
                self.appIcon = image
                resultHandler(.contentAvailable)
            }
        }
        promoView.backgroundQueue.addOperation(operation)
    }

    public func contentView(for promoView: PromoView) -> PromoContentView {
        var title = "Hope you're enjoying this app!"
        if let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] {
            title = "Hope you're enjoying \(appName)!"
        }
        let view = promoView.dequeueContentView(for: PromoTableListContentView.self)
        view.configure(title: title,
                       detailText: "Please make sure to rate it on the App Store when you get a chance!",
                       image: appIcon)
        return view
    }

    public func cornerRadius(for promoView: PromoView, with contentPadding: UIEdgeInsets) -> CGFloat {
        promoView.frame.height * 0.3
    }
}
