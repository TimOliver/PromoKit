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
    public func registerContentViewClasses(for promoView: PromoView) {
        
    }
    

    public var identifier: String { PromoProviderIdentifier.appRater }

    public func fetchNewContent(with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        resultHandler(.contentAvailable)
    }

    public func contentView(for promoView: PromoView) -> PromoContentView {
        return promoView.dequeueContentView(with: PromoContentViewReuseIdentifier.blank)
    }
}

extension PromoProviderIdentifier {
    static public let appRater = "PMKPromoAppRaterProvider"
}
