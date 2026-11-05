import XCTest

final class SmallScreenTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    @MainActor private func launch(knownVocabulary: Bool = false, exhausted: Bool = false, longReading: Bool = false) {
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["JPLEARN_UI_TEST_SESSION"] = UUID().uuidString
        if knownVocabulary || exhausted || longReading { app.launchEnvironment["JPLEARN_UI_TEST_KNOWN_VOCABULARY"] = "1" }
        if exhausted { app.launchEnvironment["JPLEARN_UI_TEST_EXHAUSTED"] = "1" }
        if longReading { app.launchEnvironment["JPLEARN_UI_TEST_LONG_READING"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 10))
    }
    @MainActor private func visible(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let exists = element.waitForExistence(timeout: 5)
        if !exists { print(app.debugDescription); screenshot("SE3-MissingControl") }
        XCTAssertTrue(exists, file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(element.frame), "Control is outside the SE3 screen", file: file, line: line)
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testRecallAndRatingControlsFitOnSE3() {
        launch()
        XCTAssertEqual(app.frame.width, 375, accuracy: 1)
        XCTAssertEqual(app.frame.height, 667, accuracy: 1)
        visible(app.buttons["today.start"])
        screenshot("SE3-Today")
        app.buttons["today.start"].tap()
        visible(app.buttons["study.reveal"])
        XCTAssertFalse(app.scrollViews["study.textScroll"].exists)
        app.buttons["study.reveal"].tap()
        for rating in 1...4 { visible(app.buttons["study.grade.\(rating)"]) }
        screenshot("SE3-Recall")
    }

    @MainActor func testKeyboardLeavesTheAnswerActionVisible() {
        launch()
        app.buttons["today.start"].tap()
        let field = app.textFields["study.kanaInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("a")
        visible(app.buttons["study.reveal"])
        screenshot("SE3-Keyboard")
        app.buttons["study.reveal"].tap()
        visible(app.buttons["study.continue"])
    }

    @MainActor func testGrammarAndReadingKeepActionsVisible() {
        launch(knownVocabulary: true)
        app.buttons["today.start"].tap()
        var checkedGrammar = false
        for _ in 0..<40 {
            if app.scrollViews["study.readingScroll"].exists {
                for choice in 0...2 { visible(app.buttons["study.choice.\(choice)"]) }
                screenshot("SE3-Reading")
                XCTAssertTrue(app.staticTexts["study.readingCoverage"].exists)
                let before = app.buttons["study.choice.0"].frame
                app.scrollViews["study.readingScroll"].swipeUp()
                XCTAssertEqual(app.buttons["study.choice.0"].frame, before)
                app.buttons["study.choice.0"].tap()
                visible(app.buttons["study.continue"])
                screenshot("SE3-Reading-Feedback")
                XCTAssertTrue(checkedGrammar)
                return
            }
            if app.buttons["study.reveal"].exists { app.buttons["study.reveal"].tap() }
            else if app.buttons["study.grade.3"].exists { app.buttons["study.grade.3"].tap() }
            else if app.buttons["study.continue"].exists { app.buttons["study.continue"].tap() }
            else if app.buttons["study.choice.0"].exists {
                for choice in 0...2 { visible(app.buttons["study.choice.\(choice)"]) }
                screenshot("SE3-Grammar")
                checkedGrammar = true
                app.buttons["study.choice.0"].tap()
                visible(app.buttons["study.continue"])
            }
        }
        XCTFail("Reading task did not appear")
    }

    @MainActor func testExhaustedPlanDoesNotStartAnotherLibraryLoop() {
        launch(exhausted: true)
        XCTAssertFalse(app.buttons["today.start"].isEnabled)
        XCTAssertTrue(app.buttons["today.start"].label.contains("今日安排已完成"))
        XCTAssertFalse(app.scrollViews["study.readingScroll"].exists)
        screenshot("SE3-CompletedPlan")
    }

    @MainActor func testLongReadingKeepsCoverageAndAnswerControlsVisible() {
        launch(longReading: true)
        app.buttons["today.start"].tap()
        let scroll = app.scrollViews["study.readingScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["study.readingCoverage"].label.contains("100%"))
        for choice in 0...2 { visible(app.buttons["study.choice.\(choice)"]) }
        let fixed = app.buttons["study.choice.0"].frame
        scroll.swipeUp()
        XCTAssertEqual(fixed, app.buttons["study.choice.0"].frame)
        screenshot("SE3-LongReading")
        app.buttons["study.choice.0"].tap()
        visible(app.buttons["study.continue"])
        screenshot("SE3-LongReading-Feedback")
        app.buttons["study.continue"].tap()
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 5))
    }

    @MainActor func testPauseStopsTheVisibleTimer() {
        launch()
        app.buttons["today.start"].tap()
        XCTAssertTrue(app.buttons["study.pause"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["study.pause"].tap()
        XCTAssertTrue(app.buttons["study.resume"].waitForExistence(timeout: 5))
        let timer = app.descendants(matching: .any).matching(identifier: "study.timer").firstMatch
        let paused = timer.label
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(timer.label, paused)
        app.buttons["study.resume"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", paused), object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }
}
