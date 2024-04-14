//
//  PromoAppRaterProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 12/2/2024.
//

import UIKit

/// A promo provider that displays a call-to-action to rate this app on the App Store.
/// This can be a great default provider when all other providers are unavailable (such as when offline).
@objc(PMKPromoAppRaterProvider)
public class PromoAppRaterProvider: NSObject, PromoProvider {

    // A static identifier that can be used to fetch this provider
    public var identifier: String { PromoProviderIdentifier.appRater }

    // The name of the app icon in the app bundle
    private var appIconName: String?

    // The icon associated with this app
    private var appIcon: UIImage?

    // The width x height of the app icon
    private var iconDimension: CGFloat

    /// Creates a new provider with the app's associated app icon
    /// - Parameters:
    ///   - appIconName: The name of the app icon in the asset bundle
    ///   - maxIconDimension: The maximum expected size the icon will be rendered at, in points
    init(appIconName: String = "AppIcon", maxIconDimension: CGFloat = 96.0) {
        self.appIconName = appIconName
        self.iconDimension = maxIconDimension
    }

    public func fetchNewContent(for promoView: PromoView, with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        guard let appIconName, let appIcon = UIImage(named: appIconName) else {
            resultHandler(.contentAvailable)
            return
        }

        let scale = promoView.traitCollection.displayScale
        let operation = BlockOperation()
        operation.addExecutionBlock {
            guard !operation.isCancelled else { return }

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
        let view = promoView.dequeueContentView(for: PromoTableListContentView.self)
        view.configure(title: "Hope you're enjoying iComics!", 
                       detailText: "Please make sure to rate it on the App Store when you get a chance!",
                       image: appIcon)
        return view
    }
}

extension PromoProviderIdentifier {
    static public let appRater = "PMKPromoAppRaterProvider"
}
