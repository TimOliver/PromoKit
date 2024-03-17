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
        promoView.frame.size = promoView.sizeThatFits(view.bounds.size)
        promoView.center = view.center
    }
}

