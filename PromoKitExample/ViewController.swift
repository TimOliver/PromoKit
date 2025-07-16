//
//  ViewController.swift
//  PromoKit
//
//  Created by Tim Oliver on 29/1/2024.
//

import UIKit

class ViewController: UIViewController {

    let promoView = PromoView()

    override func viewDidLoad() {
        super.viewDidLoad()

        promoView.rootViewController = self
        promoView.delegate = self

        // Native ad layout
        promoView.providers = [PromoCloudEventProvider(containerIdentifier: "iCloud.dev.tim.promokit"),
                               PromoNativeAdProvider(adUnitID: "ca-app-pub-3940256099942544/5406332512")]

        // Banner ad layout
//        promoView.providers = [
//            //PromoBannerAdProvider(adUnitID: "ca-app-pub-3940256099942544/2435281174"),
//            PromoAppRaterProvider(appIconName: "AppIcon", maxIconDimension: 128)
//        ]

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
            self.promoView.cancelTapInteraction(animated: true)
        }

        view.addSubview(promoView)
    }

    override func viewDidLayoutSubviews() {

        layoutAdView()
        promoView.reloadIfNeeded()

//        //promoView.defaultContentPadding = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
//        promoView.frame.size = CGSize(width: 336, height: 66) //CGSize(width: 728, height: 90)
    }

    private func layoutAdView() {
        let safeAreaInset = max(view.safeAreaInsets.top, view.safeAreaInsets.bottom)
        let layoutMargins = view.layoutMargins.left
        let promoBounds = view.bounds.insetBy(dx: layoutMargins, dy: safeAreaInset)
        promoView.frame.size = promoView.sizeThatFits(promoBounds.size)
        promoView.center = view.center
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
}

extension ViewController: PromoViewDelegate {
    func promoView(_ promoView: PromoView, didUpdateProvider provider: any PromoProvider) {
        layoutAdView()
    }
}
