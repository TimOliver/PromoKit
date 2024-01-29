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

        promoView.frame.size = CGSize(width: 300, height: 270)
        view.addSubview(promoView)
    }

    override func viewDidLayoutSubviews() {
        promoView.center = view.center
    }
}

