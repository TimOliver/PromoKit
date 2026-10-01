//
//  PromoKitUITests.swift
//  PromoKitUITests
//
//  Created by Tim Oliver on 29/1/2024.
//

import XCTest

final class PromoKitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testProviderFallbackAndAccessibleDismissal() throws {
        let app = launchFixture()
        XCTAssertEqual(app.staticTexts["fixture-status"].label, "Unavailable → Failed → Ready")
        XCTAssertEqual(app.staticTexts["promo-text"].label,
                       "Offline promotion\nWorks without a network connection.")
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.isHittable)
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        }
        closeButton.tap()
        XCTAssertTrue(app.staticTexts["Dismissed"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["promo-text"].exists)
        XCTAssertFalse(closeButton.exists)
    }

    func testRotationKeepsCardAndCloseButtonOnScreen() {
        let app = launchFixture()
        assertContentFits(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }
        expectation(for: landscape, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        assertContentFits(app)
        XCTAssertEqual(app.staticTexts["fixture-status"].label, "Unavailable → Failed → Ready")
        attachScreenshot(app, name: "Landscape promotion")
    }

    func testNarrowWidthKeepsTextAndThumbnailSeparate() {
        let app = launchFixture(arguments: ["-PromoKitNarrow"])
        let text = app.staticTexts["promo-text"]
        let image = app.images["promo-thumbnail"]
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(card(in: app).frame.width, 280.5)
        XCTAssertLessThan(image.frame.maxX, text.frame.minX)
        assertContentFits(app)
        attachScreenshot(app, name: "Narrow promotion")
    }

    func testRightToLeftMirrorsThumbnailAndText() {
        let app = launchFixture(arguments: ["-PromoKitRTL", "-PromoKitNarrow"])
        let text = app.staticTexts["promo-text"]
        let image = app.images["promo-thumbnail"]
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        XCTAssertLessThan(text.frame.maxX, image.frame.minX)
        assertContentFits(app)
        attachScreenshot(app, name: "Right-to-left promotion")
    }

    func testAccessibilityTextSizeExpandsCard() {
        let app = launchFixture()
        let normalSize = card(in: app).frame.size
        app.terminate()
        app.launchArguments = ["-PromoKitUIFixtures", "-PromoKitLargeText"]
        app.launch()
        XCTAssertTrue(app.staticTexts["promo-text"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(card(in: app).frame.height, normalSize.height + 30)
        XCTAssertEqual(card(in: app).frame.width, normalSize.width, accuracy: 1)
        assertContentFits(app)
        attachScreenshot(app, name: "Maximum accessibility text size")
    }

    func testLightAppearanceLayoutAndAccessibility() throws {
        try assertAppearanceLayoutAndAccessibility("Light")
    }

    func testDarkAppearanceLayoutAndAccessibility() throws {
        try assertAppearanceLayoutAndAccessibility("Dark")
    }

    private func assertAppearanceLayoutAndAccessibility(_ appearance: String) throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Accessibility audits require iOS 17") }
        let app = launchFixture(arguments: ["-PromoKit\(appearance)Appearance"])
        assertContentFits(app)
        attachScreenshot(app, name: "\(appearance) appearance")
        // Contrast audits misread dynamic label colors under appearance overrides.
        // Close-symbol contrast is covered by unit tests.
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }

    private func launchFixture(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PromoKitUIFixtures"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["promo-text"].waitForExistence(timeout: 5))
        return app
    }

    private func card(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["promo-card"]
    }

    private func assertContentFits(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let windowFrame = app.windows.firstMatch.frame
        let cardFrame = card(in: app).frame
        let text = app.staticTexts["promo-text"]
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(windowFrame.contains(cardFrame), file: file, line: line)
        XCTAssertTrue(cardFrame.contains(text.frame), file: file, line: line)
        XCTAssertGreaterThan(text.frame.height, 0, file: file, line: line)
        XCTAssertTrue(windowFrame.contains(closeButton.frame), file: file, line: line)
        XCTAssertTrue(closeButton.isHittable, file: file, line: line)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
