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

    static var usesUIFixtures: Bool {
        ProcessInfo.processInfo.arguments.contains("-PromoKitUIFixtures")
    }

    static var isHostedTestRun: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["PROMOKIT_TESTING"] == "1"
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        guard !Self.usesUIFixtures, !Self.isHostedTestRun else { return true }
        MobileAds.shared.start { status in
            print("STATUS \(status)")
        }
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["a9f2a33593ee7736bd2aa820b18c70da"]
        return true
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}
