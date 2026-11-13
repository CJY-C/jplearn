import XCTest
import LearningCore
@testable import JPLearn

final class ReadingProgressTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @MainActor func testReadingQuestionProgressSurvivesReopeningWithoutInventingWordReviews() throws {
        let folder = try directory()
        let first = try AppModel(storageDirectory: folder)
        let reading = try XCTUnwrap(first.pack.readings.first { $0.id == "r033" })
        try first.startAssessment(reading)
        let entryID = try XCTUnwrap(first.checkpoint?.current?.id)
        let question = reading.allQuestions[0]
        try first.recordReadingSelection(entryID: entryID, questionID: question.id, selection: question.answerIndex, assisted: false)
        try first.recordReadingSelection(entryID: entryID, questionID: question.id, selection: question.answerIndex, assisted: false)
        XCTAssertEqual(first.events.filter { $0.kind == .questionAttempt }.count, 1)
        XCTAssertFalse(first.events.contains { $0.kind == .readingAttempt || $0.kind == .review })

        let restored = try AppModel(storageDirectory: folder)
        try restored.resumeSession()
        XCTAssertEqual(restored.checkpoint?.current?.id, entryID)
        XCTAssertEqual(restored.checkpoint?.questionIndex, 1)
        let second = reading.allQuestions[1]
        try restored.recordReadingSelection(entryID: entryID, questionID: second.id,
            selection: (second.answerIndex + 1) % second.choices.count, assisted: false)
        try restored.advanceReadingQuestion(entryID: entryID, questionID: second.id)
        XCTAssertNil(restored.checkpoint?.current)
        XCTAssertEqual(restored.events.filter { $0.kind == .readingAttempt }.count, 1)
        XCTAssertEqual(restored.events.first { $0.kind == .readingAttempt }?.value, "incorrect")
        XCTAssertTrue(try ReviewScheduler().dueKeys(events: restored.events, pack: restored.pack).isEmpty)
        let archive = try ArchiveCodec.decode(restored.exportBackup())
        XCTAssertEqual(archive.schemaVersion, 3)
        XCTAssertEqual(archive.events, restored.events)
    }

    @MainActor func testStaleContinueCannotAdvanceTheNextQuestion() throws {
        let model = try AppModel(storageDirectory: directory())
        let reading = try XCTUnwrap(model.pack.readings.first { $0.id == "r033" })
        try model.startAssessment(reading)
        let id = try XCTUnwrap(model.checkpoint?.current?.id), question = reading.allQuestions[0]
        try model.recordReadingSelection(entryID: id, questionID: question.id, selection: question.answerIndex, assisted: false)
        try model.advanceReadingQuestion(entryID: id, questionID: question.id)
        try model.advanceReadingQuestion(entryID: id, questionID: question.id)
        XCTAssertEqual(model.checkpoint?.questionIndex, 1)
        XCTAssertNotNil(model.checkpoint?.current)
    }

    @MainActor func testReadingAidRemainsAssistedAfterClosingAndReopening() throws {
        let folder = try directory()
        let first = try AppModel(storageDirectory: folder)
        let reading = try XCTUnwrap(first.pack.readings.first { $0.id == "r033" })
        try first.startAssessment(reading)
        let entry = try XCTUnwrap(first.checkpoint?.current?.id)
        try first.markAssisted(entryID: entry)
        let restored = try AppModel(storageDirectory: folder)
        try restored.resumeSession()
        for question in reading.allQuestions {
            try restored.recordReadingSelection(entryID: entry, questionID: question.id,
                                                 selection: question.answerIndex, assisted: false)
            try restored.advanceReadingQuestion(entryID: entry, questionID: question.id)
        }
        let attempts = restored.events.filter { $0.kind == .questionAttempt }
        XCTAssertEqual(attempts.count, reading.allQuestions.count)
        XCTAssertTrue(attempts.allSatisfy { $0.assisted && $0.correct == false })
        XCTAssertEqual(restored.events.first { $0.kind == .readingAttempt }?.value, "incorrect")
        XCTAssertFalse(restored.events.contains { $0.kind == .review })
    }

    @MainActor func testPlacementHasNoFSRSHistory() throws {
        let model = try AppModel(storageDirectory: directory())
        try model.recordPlacement(moduleID: "intro1", passed: true)
        XCTAssertEqual(model.events.count, 1)
        XCTAssertEqual(model.events[0].kind, .placement)
        XCTAssertTrue(try ReviewScheduler().dueKeys(events: model.events, pack: model.pack).isEmpty)
    }
}
