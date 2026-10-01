//
//  ViewController.swift
//  PromoKit
//
//  Created by Tim Oliver on 29/1/2024.
//

import UIKit
import PromoKit
import PromoKitGoogleAds

class ViewController: UIViewController {

    let promoView = PromoView()
    private let fixtureStatusLabel = UILabel()
    private var fixtureFetches: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        guard AppDelegate.usesUIFixtures || !AppDelegate.isHostedTestRun else { return }

        promoView.showCloseButton = true
        promoView.rootViewController = self
        promoView.delegate = self

        if AppDelegate.usesUIFixtures {
            configureUIFixture()
        } else {
            promoView.providers = [PromoCloudEventProvider(containerIdentifier: "iCloud.dev.tim.promokit"),
                                   PromoNativeAdProvider(adUnitID: "ca-app-pub-3940256099942544/5406332512"),
                                   PromoAppRaterProvider(appIconName: "AppIcon")]
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) { [weak self] in
                self?.promoView.cancelTapInteraction(animated: true)
            }
        }
        view.addSubview(promoView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard promoView.superview != nil else { return }
        layoutAdView()
        promoView.reloadIfNeeded()
    }

    private func layoutAdView() {
        let safeBounds = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 24, dy: 32)
        var fittingSize = safeBounds.size
        if AppDelegate.usesUIFixtures {
            fixtureStatusLabel.frame = CGRect(x: safeBounds.minX, y: safeBounds.minY,
                                              width: safeBounds.width, height: 40)
            fittingSize.height = max(0, fittingSize.height - 80)
            if ProcessInfo.processInfo.arguments.contains("-PromoKitNarrow") {
                fittingSize.width = min(fittingSize.width, 280)
            }
        }
        promoView.frame.size = promoView.sizeThatFits(fittingSize)
        promoView.center = CGPoint(x: safeBounds.midX, y: safeBounds.midY)
    }

    private func configureUIFixture() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PromoKitLightAppearance") {
            overrideUserInterfaceStyle = .light
        } else if arguments.contains("-PromoKitDarkAppearance") {
            overrideUserInterfaceStyle = .dark
        }
        let rightToLeft = arguments.contains("-PromoKitRTL")
        view.semanticContentAttribute = rightToLeft ? .forceRightToLeft : .forceLeftToRight
        if #available(iOS 17.0, *) {
            traitOverrides.layoutDirection = rightToLeft ? .rightToLeft : .leftToRight
            traitOverrides.preferredContentSizeCategory = arguments.contains("-PromoKitLargeText")
                ? .accessibilityExtraExtraExtraLarge : .large
        }

        fixtureStatusLabel.accessibilityIdentifier = "fixture-status"
        fixtureStatusLabel.font = .systemFont(ofSize: 14)
        fixtureStatusLabel.textAlignment = .center
        fixtureStatusLabel.text = "Loading"
        view.addSubview(fixtureStatusLabel)
        promoView.accessibilityIdentifier = "promo-card"
        promoView.backgroundColor = .secondarySystemBackground

        let recordFetch: (String) -> Void = { [weak self] name in
            self?.fixtureFetches.append(name)
        }
        promoView.providers = [
            FixtureProvider(name: "Unavailable", result: .noContentAvailable, recordFetch: recordFetch),
            FixtureProvider(name: "Failed", result: .fetchRequestFailed, recordFetch: recordFetch),
            FixtureProvider(name: "Ready", result: .contentAvailable, recordFetch: recordFetch)
        ]
    }
}

extension ViewController: PromoViewDelegate {
    func promoView(_ promoView: PromoView, didUpdateProvider provider: any PromoProvider) {
        if AppDelegate.usesUIFixtures {
            fixtureStatusLabel.text = fixtureFetches.joined(separator: " → ")
        }
        layoutAdView()
    }

    func promoViewProviderDidTapCloseButton(_ promoView: PromoView) {
        promoView.removeFromSuperview()
        if AppDelegate.usesUIFixtures {
            fixtureStatusLabel.text = "Dismissed"
        }
    }
}

/// Local data exercises the real provider coordinator and built-in table content without services.
private final class FixtureProvider: NSObject, PromoProvider {
    private let name: String
    private let result: PromoProviderFetchContentResult
    private let recordFetch: (String) -> Void
    private let appRater = PromoAppRaterProvider()

    init(name: String, result: PromoProviderFetchContentResult, recordFetch: @escaping (String) -> Void) {
        self.name = name
        self.result = result
        self.recordFetch = recordFetch
    }

    func fetchNewContent(for promoView: PromoView, with resultHandler: @escaping PromoProviderContentFetchHandler) {
        recordFetch(name)
        resultHandler(result)
    }

    func preferredContentSize(fittingSize: CGSize, for promoView: PromoView) -> CGSize {
        appRater.preferredContentSize(fittingSize: fittingSize, for: promoView)
    }

    func contentView(for promoView: PromoView) -> PromoContentView {
        let content = appRater.contentView(for: promoView) as! PromoTableListContentView
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
        content.configure(title: "Offline promotion", detailText: "Works without a network connection.", image: image)
        content.label.accessibilityIdentifier = "promo-text"
        content.imageView.isAccessibilityElement = true
        content.imageView.accessibilityIdentifier = "promo-thumbnail"
        content.imageView.accessibilityLabel = "Promo thumbnail"
        return content
    }
}
