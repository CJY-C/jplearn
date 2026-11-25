import XCTest
@testable import LearningCore

final class ReadingAttemptJournalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let device = UUID()

    private func reading(_ id: String, pack: ContentPack) throws -> ReadingPassage {
        try XCTUnwrap(pack.readings.first { $0.id == id })
    }
    private func known(_ reading: ReadingPassage) -> [LearningEvent] {
        Set((reading.vocabulary ?? []).compactMap(\.itemID)).map {
            LearningEvent(deviceID: device, timestamp: now, kind: .review, targetID: $0, skill: .meaning, rating: 3)
        } + (reading.grammarIDs ?? []).map {
            LearningEvent(deviceID: device, timestamp: now, kind: .review, targetID: $0, skill: .grammar, rating: 3)
        }
    }

    func testSingleQuestionCompletionIsSavedWithAnswerBeforeContinue() throws {
        let pack = try ContentPack.bundled(), reading = try reading("r009", pack: pack)
        XCTAssertEqual(reading.allQuestions.count, 1)
        var checkpoint = SessionCheckpoint(tasks: [.reading(reading.id), .reading(reading.id), .exercise("e001a")])
        let entry = try XCTUnwrap(checkpoint.current), question = reading.allQuestions[0]
        let records = ReadingAttemptJournal.answer(reading: reading, entryID: entry.id, deviceID: device,
            questionID: question.id, selection: question.answerIndex, assisted: false, events: [], now: now)
        XCTAssertEqual(records.map(\.kind), [.questionAttempt, .readingAttempt])
        XCTAssertEqual(records.last?.id, entry.id)
        XCTAssertEqual(records.last?.value, "correct")
        let persisted = try EventMerge.merge(known(reading), records)
        checkpoint.recover(recordedIDs: Set(persisted.map(\.id)))
        checkpoint.removeUnavailableReadings(pack: pack, events: persisted, now: now)
        XCTAssertEqual(checkpoint.current?.task.id, "exercise:e001a")
        XCTAssertFalse(SessionPlanner.readingAvailable(reading, pack: pack, events: persisted,
                                                       now: now.addingTimeInterval(600)))
        XCTAssertTrue(ReadingAttemptJournal.answer(reading: reading, entryID: entry.id, deviceID: device,
            questionID: question.id, selection: question.answerIndex, assisted: false, events: persisted, now: now).isEmpty)
        XCTAssertFalse(records.contains { $0.kind == .review }, "Reading cannot invent word or grammar reviews")
    }

    func testPartialReadingCannotBeRecordedAsCompleteAndLastQuestionIsAtomic() throws {
        let pack = try ContentPack.bundled(), reading = try reading("r033", pack: pack), entry = UUID()
        XCTAssertGreaterThan(reading.allQuestions.count, 1)
        var history: [LearningEvent] = []
        for (index, q) in reading.allQuestions.enumerated() {
            let records = ReadingAttemptJournal.answer(reading: reading, entryID: entry, deviceID: device,
                questionID: q.id, selection: q.answerIndex, assisted: index == 0, events: history, now: now)
            XCTAssertEqual(records.filter { $0.kind == .readingAttempt }.count,
                index == reading.allQuestions.count - 1 ? 1 : 0)
            history = try EventMerge.merge(history, records)
        }
        let completion = try XCTUnwrap(history.first { $0.kind == .readingAttempt })
        XCTAssertTrue(completion.assisted)
        XCTAssertEqual(completion.value, "incorrect")
        XCTAssertEqual(history.filter { $0.kind == .readingAttempt }.count, 1)
    }

    func testLegacyFinalAnswerWithoutCompletionCanBeRecoveredIdempotently() throws {
        let pack = try ContentPack.bundled(), reading = try reading("r009", pack: pack), entry = UUID()
        let q = reading.allQuestions[0]
        let legacy = LearningEvent(deviceID: device, timestamp: now, kind: .questionAttempt, targetID: q.id,
            value: String(q.answerIndex), contextID: entry.uuidString, correct: true)
        let recovered = try XCTUnwrap(ReadingAttemptJournal.completion(reading: reading, entryID: entry,
            deviceID: device, events: [legacy], now: now))
        XCTAssertEqual(recovered.id, entry)
        XCTAssertEqual(recovered.value, "correct")
        XCTAssertNil(ReadingAttemptJournal.completion(reading: reading, entryID: entry,
            deviceID: device, events: [legacy, recovered], now: now))
        XCTAssertNil(ReadingAttemptJournal.completion(reading: reading, entryID: UUID(),
            deviceID: device, events: [legacy], now: now), "Another session cannot borrow this answer")
    }

    func testRestoredQueueRemovesUnattemptedDuplicatesWithoutLosingOtherTasks() throws {
        let pack = try ContentPack.bundled(), reading = try reading("r009", pack: pack)
        var checkpoint = SessionCheckpoint(tasks: [.reading(reading.id), .exercise("e001a"), .reading(reading.id)])
        let first = checkpoint.entries[0].id, exercise = checkpoint.entries[1].id
        checkpoint.removeUnavailableReadings(pack: pack, events: known(reading), now: now)
        XCTAssertEqual(checkpoint.entries.map(\.id), [first, exercise])
        checkpoint.index = 1
        checkpoint.removeUnavailableReadings(pack: pack, events: known(reading), now: now)
        XCTAssertEqual(checkpoint.current?.id, exercise)

        var legacy = SessionCheckpoint(tasks: [.reading(reading.id), .reading(reading.id), .exercise("e001a")])
        legacy.index = 1
        legacy.removeUnavailableReadings(pack: pack, events: known(reading), now: now)
        XCTAssertEqual(legacy.current?.task.id, "exercise:e001a",
            "A previously visited passage cannot recur in the same saved arrangement, even with a legacy journal gap")
    }
}
