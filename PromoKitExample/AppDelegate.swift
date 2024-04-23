//
//  AppDelegate.swift
//  PromoKit
//
//  Created by Tim Oliver on 29/1/2024.
//

import UIKit
import GoogleMobileAds

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    public var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        GADMobileAds.sharedInstance().start { status in
            print("STATUS \(status)")
        }
        return true
    }

}

