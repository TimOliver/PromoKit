//
//  PromoKitUITestsLaunchTests.swift
//  PromoKitUITests
//
//  Created by Tim Oliver on 29/1/2024.
//

import XCTest

final class PromoKitUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PromoKitUIFixtures"]
        app.launch()
        XCTAssertTrue(app.staticTexts["promo-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close"].isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Offline fixture launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
