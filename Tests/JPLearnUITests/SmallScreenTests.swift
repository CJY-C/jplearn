import XCTest
import UIKit

final class SmallScreenTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    @MainActor private func launch(knownVocabulary: Bool = false, exhausted: Bool = false, longReading: Bool = false, readingID: String? = nil, wordID: String? = nil, exerciseID: String? = nil, largeText: Bool = false) {
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.extraExtraExtraLarge.rawValue] }
        app.launchEnvironment["JPLEARN_UI_TEST_SESSION"] = UUID().uuidString
        if knownVocabulary || exhausted || longReading || readingID != nil { app.launchEnvironment["JPLEARN_UI_TEST_KNOWN_VOCABULARY"] = "1" }
        if exhausted { app.launchEnvironment["JPLEARN_UI_TEST_EXHAUSTED"] = "1" }
        if longReading || readingID != nil { app.launchEnvironment["JPLEARN_UI_TEST_LONG_READING"] = "1" }
        if let readingID = readingID { app.launchEnvironment["JPLEARN_UI_TEST_READING_ID"] = readingID }
        if let wordID = wordID { app.launchEnvironment["JPLEARN_UI_TEST_WORD_ID"] = wordID }
        if let exerciseID = exerciseID { app.launchEnvironment["JPLEARN_UI_TEST_EXERCISE_ID"] = exerciseID }
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
    @MainActor private func visibleChoices(file: StaticString = #filePath, line: UInt = #line) {
        var previous: CGRect?
        for index in 0...2 {
            let button = app.buttons["study.choice.\(index)"]
            visible(button, file: file, line: line)
            let frame = button.frame
            XCTAssertGreaterThanOrEqual(frame.height, 44, "Answer needs a full touch target", file: file, line: line)
            if let previous = previous {
                XCTAssertGreaterThanOrEqual(frame.minY, previous.maxY + 6,
                    "Adjacent answers must have a visible gap: \(previous), \(frame)", file: file, line: line)
            }
            for label in button.descendants(matching: .staticText).allElementsBoundByIndex {
                XCTAssertTrue(frame.insetBy(dx: -1, dy: -1).contains(label.frame),
                    "Answer label must fit its button: \(label.label)", file: file, line: line)
            }
            previous = frame
        }
    }
    @MainActor private func scrollWordNotes() {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let bottom = app.staticTexts["按刚才回想的表现选择"].frame.minY - 18
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: bottom))
        let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: 170))
        start.press(forDuration: 0.1, thenDragTo: end)
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

    @MainActor func testExpandedWordNotesKeepRatingsVisibleOnSE3() {
        launch(wordID: "vn5546")
        app.buttons["today.start"].tap()
        visible(app.buttons["study.reveal"])
        app.buttons["study.reveal"].tap()
        for rating in 1...4 { visible(app.buttons["study.grade.\(rating)"]) }
        let fixed = app.buttons["study.grade.3"].frame
        let scroll = app.scrollViews["study.textScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "小动物常用匹")).firstMatch
        XCTAssertTrue(note.exists)
        scrollWordNotes()
        visible(note)
        XCTAssertLessThanOrEqual(note.frame.maxY, app.staticTexts["按刚才回想的表现选择"].frame.minY)
        XCTAssertEqual(fixed, app.buttons["study.grade.3"].frame)
        visible(app.buttons["study.grade.3"])
        screenshot("SE3-ExpandedWord-Notes")
        app.buttons["study.grade.3"].tap()
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 5))
    }

    @MainActor func testLargeWordNotesScrollAboveFixedRatingsOnSE3() {
        launch(wordID: "vn5546", largeText: true)
        app.buttons["today.start"].tap()
        app.buttons["study.reveal"].tap()
        for rating in 1...4 { visible(app.buttons["study.grade.\(rating)"]) }
        let fixed = app.buttons["study.grade.3"].frame
        let scroll = app.scrollViews["study.textScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "小动物常用匹")).firstMatch
        let originalY = note.frame.minY
        scrollWordNotes()
        XCTAssertLessThan(note.frame.minY, originalY - 5)
        XCTAssertEqual(fixed, app.buttons["study.grade.3"].frame)
        for rating in 1...4 { visible(app.buttons["study.grade.\(rating)"]) }
        screenshot("SE3-ExpandedWord-LargeText")
    }

    @MainActor func testLongN4GrammarHintScrollsAboveFixedChoicesOnSE3() {
        launch(exerciseID: "egn426g", largeText: true)
        app.buttons["today.start"].tap()
        visible(app.buttons["study.hintButton"])
        let fixed = app.buttons["study.choice.0"].frame
        app.buttons["study.hintButton"].tap()
        let hint = app.staticTexts["study.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        let originalY = hint.frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: fixed.minY - 18))
        let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: 170))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertLessThan(hint.frame.minY, originalY - 5)
        XCTAssertEqual(fixed, app.buttons["study.choice.0"].frame)
        visibleChoices()
        screenshot("SE3-N4-Grammar-Hint-LargeText")
        app.buttons["study.choice.0"].tap()
        visible(app.buttons["study.continue"])
    }

    @MainActor func testLongN4SentenceScrollsBeforeHintAboveFixedChoices() {
        launch(exerciseID: "egn470e", largeText: true)
        app.buttons["today.start"].tap()
        let scroll = app.scrollViews["study.textScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        visibleChoices()
        let fixed = app.buttons["study.choice.0"].frame
        let sentence = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "眠れなくて困りましたが")).firstMatch
        XCTAssertTrue(sentence.waitForExistence(timeout: 5))
        let originalY = sentence.frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: fixed.minY - 18))
        let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: 170))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertLessThan(sentence.frame.minY, originalY - 5)
        XCTAssertEqual(fixed, app.buttons["study.choice.0"].frame)
        visible(app.buttons["study.hintButton"])
        visibleChoices()
        screenshot("SE3-N4-LongSentence-LargeText")
        app.buttons["study.choice.0"].tap()
        visible(app.buttons["study.continue"])
    }

    @MainActor func testNewN4NoticeKeepsQuantityAndDeadlineQuestionsVisible() {
        launch(readingID: "rn4120", largeText: true)
        app.buttons["today.start"].tap()
        XCTAssertTrue(app.staticTexts["study.readingCoverage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["study.readingCoverage"].label.contains("100%"))
        for index in 1...2 {
            XCTAssertTrue(app.staticTexts["理解 \(index) / 2"].waitForExistence(timeout: 5))
            visibleChoices()
            screenshot("SE3-N4-Notice-LargeText-Question\(index)")
            app.buttons["study.choice.0"].tap()
            visible(app.buttons["study.continue"])
            app.buttons["study.continue"].tap()
        }
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 5))
    }

    @MainActor func testN4VoiceReadingKeepsBothQuestionActionsVisible() {
        launch(readingID: "rn4020")
        app.buttons["today.start"].tap()
        for index in 1...2 {
            XCTAssertTrue(app.staticTexts["理解 \(index) / 2"].waitForExistence(timeout: 5))
            visibleChoices()
            screenshot("SE3-N4-Voice-Question\(index)")
            app.buttons["study.choice.0"].tap()
            visible(app.buttons["study.continue"])
            app.buttons["study.continue"].tap()
        }
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 5))
    }

    @MainActor func testGrammarAndReadingKeepActionsVisible() {
        launch(knownVocabulary: true)
        app.buttons["today.start"].tap()
        var checkedGrammar = false
        for _ in 0..<40 {
            if app.scrollViews["study.readingScroll"].exists {
                visibleChoices()
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
                visibleChoices()
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

    @MainActor func testTwoQuestionReadingStaysOnTheSamePage() {
        launch(readingID: "r025")
        app.buttons["today.start"].tap()
        XCTAssertTrue(app.staticTexts["理解 1 / 2"].waitForExistence(timeout: 5))
        app.buttons["study.choice.0"].tap()
        visible(app.buttons["study.continue"])
        app.buttons["study.continue"].tap()
        XCTAssertTrue(app.staticTexts["理解 2 / 2"].waitForExistence(timeout: 5))
        visible(app.buttons["study.choice.0"])
        screenshot("SE3-Reading-SecondQuestion")
        app.buttons["study.choice.0"].tap()
        app.buttons["study.continue"].tap()
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 5))
    }

    @MainActor func testIntroDiagnosticFitsOnSE3() {
        launch()
        app.tabBars.buttons["课程"].tap()
        app.buttons["平假名清音"].tap()
        visible(app.buttons["intro.start"])
        screenshot("SE3-Intro")
        app.buttons["intro.start"].tap()
        for answer in [0, 1, 2, 0, 1] {
            visible(app.buttons["study.choice.\(answer)"])
            app.buttons["study.choice.\(answer)"].tap()
            app.buttons["study.continue"].tap()
        }
        XCTAssertTrue(app.staticTexts["这一项可以跳过"].waitForExistence(timeout: 5))
    }

    @MainActor func testNewN5NoticeKeepsBothQuestionActionsVisible() {
        launch(readingID: "rn5053")
        app.buttons["today.start"].tap()
        for index in 1...2 {
            XCTAssertTrue(app.staticTexts["理解 \(index) / 2"].waitForExistence(timeout: 5))
            visibleChoices()
            screenshot("SE3-N5-Notice-Question\(index)")
            app.buttons["study.choice.0"].tap()
            visible(app.buttons["study.continue"])
            app.buttons["study.continue"].tap()
        }
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 5))
    }

    @MainActor func testLongReadingKeepsCoverageAndAnswerControlsVisible() {
        launch(longReading: true)
        app.buttons["today.start"].tap()
        let scroll = app.scrollViews["study.readingScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["study.readingCoverage"].label.contains("100%"))
        visibleChoices()
        let fixed = app.buttons["study.choice.0"].frame
        let firstLine = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "昨日、友達に借りた物語")).firstMatch
        XCTAssertTrue(firstLine.exists)
        let originalY = firstLine.frame.minY
        // safeAreaInset may leave the underlying scroll view's frame extending behind the footer.
        // Start the gesture inside the visible text area, above the fixed question.
        let top = app.staticTexts["study.readingCoverage"].frame.maxY + 12
        let bottom = app.staticTexts["第二次阅读帮助说话者发现了什么？"].frame.minY - 18
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: bottom))
        let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: top))
        start.press(forDuration: 0.1, thenDragTo: end)
        screenshot("SE3-LongReading-Scrolled")
        XCTAssertLessThan(firstLine.frame.minY, originalY - 20, "Long reading text must actually move")
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
