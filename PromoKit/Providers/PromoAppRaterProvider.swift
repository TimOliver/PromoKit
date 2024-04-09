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


    public var identifier: String { PromoProviderIdentifier.appRater }

    public func fetchNewContent(with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        resultHandler(.contentAvailable)
    }

    public func contentView(for promoView: PromoView) -> PromoContentView {
        let view = promoView.dequeueContentView(for: PromoTableListContentView.self)
        view.configure(title: "Hope you're enjoying iComics!", detailText: "Please make sure to rate it on the App Store when you get a chance!")
        return view
    }
}

extension PromoProviderIdentifier {
    static public let appRater = "PMKPromoAppRaterProvider"
}
