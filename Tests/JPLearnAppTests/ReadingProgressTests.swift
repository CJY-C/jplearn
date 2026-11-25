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

    @MainActor func testMorningPassageDoesNotRepeatAfterEndingOnAnswerFeedback() throws {
        let folder = try directory(), pack = try ContentPack.bundled()
        let reading = try XCTUnwrap(pack.readings.first { $0.id == "r009" })
        let device = UUID()
        let known = Set((reading.vocabulary ?? []).compactMap(\.itemID)).map {
            LearningEvent(deviceID: device, kind: .review, targetID: $0, skill: .meaning, rating: 3)
        } + (reading.grammarIDs ?? []).map {
            LearningEvent(deviceID: device, kind: .review, targetID: $0, skill: .grammar, rating: 3)
        }
        let store = try EventStore(directory: folder)
        _ = try store.append(known, existing: [])
        let queued = SessionCheckpoint(tasks: [.reading(reading.id), .reading(reading.id), .exercise("e001a")])
        try ExchangeCoding.encoder().encode(queued).write(to: folder.appendingPathComponent("session.json"), options: .atomic)
        let model = try AppModel(storageDirectory: folder)
        XCTAssertEqual(model.checkpoint?.entries.filter { $0.task.id == "reading:r009" }.count, 1)
        let entry = try XCTUnwrap(model.checkpoint?.current?.id), q = reading.allQuestions[0]
        _ = try model.plannedTasks(minutes: 20, newWordLimit: 0)
        try model.recordReadingSelection(entryID: entry, questionID: q.id, selection: q.answerIndex, assisted: false)
        XCTAssertEqual(model.events.filter { $0.kind == .readingAttempt && $0.targetID == reading.id }.count, 1)
        // Deliberately end on feedback without pressing Continue.
        try model.finishSession()
        let reopened = try AppModel(storageDirectory: folder)
        XCTAssertFalse(try reopened.plannedTasks(minutes: 20).contains { $0.id == "reading:r009" })
        XCTAssertEqual(reopened.events.filter { $0.kind == .readingAttempt && $0.targetID == reading.id }.count, 1)
    }

    @MainActor func testEndingLegacySessionFinalizesItsAlreadySavedLastAnswer() throws {
        let folder = try directory(), pack = try ContentPack.bundled()
        let reading = try XCTUnwrap(pack.readings.first { $0.id == "r009" }), device = UUID()
        let queued = SessionCheckpoint(tasks: [.reading(reading.id), .exercise("e001a")])
        let entry = try XCTUnwrap(queued.current?.id), question = reading.allQuestions[0]
        let known = Set((reading.vocabulary ?? []).compactMap(\.itemID)).map {
            LearningEvent(deviceID: device, kind: .review, targetID: $0, skill: .meaning, rating: 3)
        } + (reading.grammarIDs ?? []).map {
            LearningEvent(deviceID: device, kind: .review, targetID: $0, skill: .grammar, rating: 3)
        }
        let legacyAnswer = LearningEvent(deviceID: device, kind: .questionAttempt, targetID: question.id,
            value: String(question.answerIndex), contextID: entry.uuidString, correct: true)
        let store = try EventStore(directory: folder)
        _ = try store.append(known + [legacyAnswer], existing: [])
        try ExchangeCoding.encoder().encode(queued).write(to: folder.appendingPathComponent("session.json"), options: .atomic)
        let model = try AppModel(storageDirectory: folder)
        try model.finishSession()
        let completed = try XCTUnwrap(model.events.first { $0.id == entry })
        XCTAssertEqual(completed.kind, .readingAttempt)
        XCTAssertEqual(completed.value, "correct")
        XCTAssertFalse(try model.plannedTasks(minutes: 20).contains { $0.id == "reading:r009" })
    }
}
