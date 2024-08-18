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

        // The location of the QuartzCore
        // framework on iOS
        let quartzCorePath =
            "/System/Library/Frameworks/" +
            "QuartzCore.framework/QuartzCore"

        // Use `dlopen` to get a handle
        // for the QuartzCore framework
        let quartzCoreHandle = dlopen(
            quartzCorePath,
            RTLD_NOW)

        // Store the address of our function
        let functionAddress = dlsym(
            quartzCoreHandle,
            "CARenderServerSetDebugOption")

        // Create a typealias representing our
        // function's param types / return type
        typealias functionType = @convention(c) (
            CInt, CInt, CInt
        ) -> Void

        // Cast the address to the
        // above function type
        let CARenderServerSetDebugOption = unsafeBitCast(
            functionAddress,
            to: functionType.self)

        // Call the function!
        CARenderServerSetDebugOption(0, 0x2, 1)

        GADMobileAds.sharedInstance().start { status in
            print("STATUS \(status)")
        }
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ "a9f2a33593ee7736bd2aa820b18c70da" ]
        return true
    }

}

