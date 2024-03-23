//
//  PromoNetworkTestProvider.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 20/3/2024.
//

import Foundation

@objc(PMKPromoNetworkTestProvider)
public class PromoNetworkTestProvider: NSObject, PromoProvider {

    public var identifier: String { "NetworkTest" }

    public var isInternetAccessRequired: Bool { true }

    public func fetchNewContent(with resultHandler: @escaping ((PromoProviderFetchContentResult) -> Void)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            resultHandler(.contentAvailable)
        }
    }
}
