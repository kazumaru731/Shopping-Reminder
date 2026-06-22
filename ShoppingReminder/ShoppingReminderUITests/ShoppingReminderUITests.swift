//
//  ShoppingReminderUITests.swift
//  ShoppingReminderUITests
//
//  Created by 南部 司真 on 2026/04/15.
//

import XCTest

final class ShoppingReminderUITests: XCTestCase {
    private let screenshotEmails = [
        "screenshot.aya@shoppingreminder.app"
    ]
    private let screenshotPassword = "Shopping123!"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        handleNotificationPromptIfNeeded()
        dismissPasswordSavePromptIfNeeded()
        loginIfNeeded(app: app)
        dismissPasswordSavePromptIfNeeded()

        let groupListTitle = app.navigationBars["マイグループ"]
        XCTAssertTrue(groupListTitle.waitForExistence(timeout: 15))
        saveScreenshot(named: "01-group-list", app: app)

        app.staticTexts["週末まとめ買い"].tap()
        XCTAssertTrue(app.navigationBars["週末まとめ買い"].waitForExistence(timeout: 10))
        saveScreenshot(named: "02-group-home", app: app)

        app.staticTexts["今夜の夕飯"].tap()
        XCTAssertTrue(app.navigationBars["今夜の夕飯"].waitForExistence(timeout: 10))
        saveScreenshot(named: "03-item-list", app: app)
    }

    @MainActor
    private func loginIfNeeded(app: XCUIApplication) {
        guard app.navigationBars["マイグループ"].waitForExistence(timeout: 2) == false else { return }

        let emailField = app.textFields.element(boundBy: 0)
        let passwordField = app.secureTextFields.element(boundBy: 0)
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        XCTAssertTrue(passwordField.exists)

        emailField.tap()
        emailField.typeText(screenshotEmails[0])

        passwordField.tap()
        passwordField.typeText(screenshotPassword)

        app.buttons["ログインする"].tap()
    }

    @MainActor
    private func handleNotificationPromptIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["許可"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
    }

    @MainActor
    private func dismissPasswordSavePromptIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNowButton = springboard.buttons["今はしない"]
        if notNowButton.waitForExistence(timeout: 3) {
            notNowButton.tap()
        }
    }

    private func saveScreenshot(named name: String, app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard
            let outputDir = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"],
            !outputDir.isEmpty
        else {
            return
        }

        let url = URL(fileURLWithPath: outputDir, isDirectory: true)
            .appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDir, isDirectory: true),
            withIntermediateDirectories: true
        )
        try? screenshot.pngRepresentation.write(to: url)
    }
}
