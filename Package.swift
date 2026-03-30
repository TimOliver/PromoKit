// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PromoKit",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "PromoKit", targets: ["PromoKit"]),
        .library(name: "PromoKitGoogleAds", targets: ["PromoKitGoogleAds"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            "12.9.0"..<"13.0.0"
        ),
    ],
    targets: [
        .target(
            name: "PromoKit",
            path: "PromoKit",
            exclude: [
                "ContentViews/PromoNativeAdContentView.swift",
                "Providers/PromoBannerAdProvider.swift",
                "Providers/PromoNativeAdProvider.swift",
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("CloudKit"),
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "PromoKitGoogleAds",
            dependencies: [
                "PromoKit",
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
            path: "PromoKit",
            exclude: [
                "PromoView.swift",
                "PromoProvider.swift",
                "PromoContentView.swift",
                "ContentViews/PromoContainerContentView.swift",
                "ContentViews/PromoTableListContentView.swift",
                "Providers/PromoAppRaterProvider.swift",
                "Providers/PromoCloudEventProvider.swift",
                "Providers/PromoNetworkTestProvider.swift",
                "Helpers",
                "Internal",
            ],
            sources: [
                "ContentViews/PromoNativeAdContentView.swift",
                "Providers/PromoBannerAdProvider.swift",
                "Providers/PromoNativeAdProvider.swift",
            ],
            swiftSettings: [
                .define("PROMOKIT_GOOGLE_ADS"),
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
            ]
        ),
        .testTarget(
            name: "PromoKitTests",
            dependencies: ["PromoKit"],
            path: "PromoKitTests"
        ),
    ]
)
