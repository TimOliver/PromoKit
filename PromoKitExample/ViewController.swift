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
        promoView.providers = [PromoAdMobBannerProvider(adUnitID: "ca-app-pub-3940256099942544/2435281174"),
                               PromoAppRaterProvider()]
        view.addSubview(promoView)
    }

    override func viewDidLayoutSubviews() {

        promoView.frame.size = promoView.sizeThatFits(view.bounds.size,
                                                      providerClass: PromoAdMobBannerProvider.self)
        promoView.center = view.center
        promoView.reloadIfNeeded()

//        //promoView.defaultContentPadding = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
//        promoView.frame.size = CGSize(width: 336, height: 66) //CGSize(width: 728, height: 90)

    }
}

