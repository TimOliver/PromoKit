//
//  PromoNetworkTestProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 20/3/2024.
//

import Foundation
import UIKit

@objc(PMKPromoNetworkTestProvider)
public class PromoNetworkTestProvider: NSObject, PromoProvider {

    public var identifier: String { "NetworkTest" }
    public var isInternetAccessRequired: Bool { true }

    public func fetchNewContent(with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            resultHandler(.contentAvailable)
        }
    }

    public func registerContentViewClasses(for promoView: PromoView) { 
        promoView.registerContentViewClass(PromoBlankContentView.self,
                                           for: PromoContentViewReuseIdentifier.blank)
    }

    public func contentView(for promoView: PromoView) -> PromoContentView {
        return promoView.dequeueContentView(with: PromoContentViewReuseIdentifier.blank)
    }

    public func preferredContentSize(for promoView: PromoView) -> CGSize {
        return CGSize(width: 300, height: 40)
    }

    public func contentPadding(for promoView: PromoView) -> UIEdgeInsets {
        return UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }
}
