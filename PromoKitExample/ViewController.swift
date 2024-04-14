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

        promoView.providers = [PromoAppRaterProvider()]
        view.addSubview(promoView)
    }

    override func viewDidLayoutSubviews() {
        //promoView.cornerRadius = 27.0
        //promoView.defaultContentPadding = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        promoView.frame.size = CGSize(width: 336, height: 66) //CGSize(width: 728, height: 90)
        promoView.center = view.center
    }
}

