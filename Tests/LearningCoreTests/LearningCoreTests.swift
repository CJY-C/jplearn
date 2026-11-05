import XCTest
@testable import LearningCore

final class LearningCoreTests: XCTestCase {
    private let deviceA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let deviceB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func review(_ id: String = "v0001", skill: Skill = .reading, grade: Int = 3,
                        time: Date? = nil, assisted: Bool = false) -> LearningEvent {
        LearningEvent(deviceID: deviceA, timestamp: time ?? now, kind: .review,
                      targetID: id, skill: skill, rating: grade, assisted: assisted)
    }

    func testBundledSampleIsCompleteAndValid() throws {
        let pack = try ContentPack.bundled()
        try pack.validate()
        XCTAssertEqual(pack.items.filter { $0.kind == "word" }.count, 182)
        XCTAssertEqual(pack.items.filter { $0.kind == "grammar" }.count, 20)
        XCTAssertEqual(pack.lessons.count, 14)
        XCTAssertEqual(pack.readings.count, 24)
        XCTAssertEqual(pack.exercises.count, 80)
    }

    func testReadingAndMeaningHaveIndependentMemory() throws {
        let states = try ReviewScheduler().replay([review()])
        XCTAssertNotNil(states[ReviewKey(itemID: "v0001", skill: .reading)])
        XCTAssertNil(states[ReviewKey(itemID: "v0001", skill: .meaning)])
    }

    func testAssistedRecallSchedulesAsFailure() throws {
        let scheduler = ReviewScheduler()
        let withHint = try scheduler.replay([review(grade: 4, assisted: true)])
        let failure = try scheduler.replay([review(grade: 1)])
        XCTAssertEqual(withHint, failure)
    }

    func testMergeIsCommutativeAndIdempotent() throws {
        let a = review()
        let b = LearningEvent(deviceID: deviceB, timestamp: now.addingTimeInterval(86400), kind: .review,
                              targetID: "v0001", skill: .reading, rating: 3)
        let left = try EventMerge.merge([a], [b, a])
        let right = try EventMerge.merge([b], [a, b])
        XCTAssertEqual(left, right)
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(try ReviewScheduler().replay(left), try ReviewScheduler().replay(Array(right.reversed())))
    }

    func testSimultaneousReviewsConverge() throws {
        let a = review(grade: 1)
        let b = LearningEvent(deviceID: deviceB, timestamp: now, kind: .review,
                              targetID: "v0001", skill: .reading, rating: 4)
        XCTAssertEqual(try ReviewScheduler().replay([a, b]), try ReviewScheduler().replay([b, a]))
    }

    func testCollisionDoesNotReplaceHistory() throws {
        let a = review()
        let collision = LearningEvent(id: a.id, deviceID: deviceA, timestamp: now, kind: .review,
                                      targetID: "v0002", skill: .reading, rating: 3)
        XCTAssertThrowsError(try EventMerge.merge([a], [collision]))
    }

    func testUnknownItemsArePreservedButNotPresented() throws {
        let history = [review("future-vocabulary")]
        let pack = try ContentPack.bundled()
        XCTAssertEqual(try EventMerge.merge([], history).count, 1)
        XCTAssertTrue(try ReviewScheduler().due(events: history, pack: pack, now: now.addingTimeInterval(86400 * 100)).isEmpty)
    }

    func testUnsupportedSchedulerAndInvalidRatingsAreRejected() {
        XCTAssertThrowsError(try review(grade: 0).validate())
        XCTAssertThrowsError(try LearningEvent(deviceID: deviceA, kind: .review, targetID: "v0001",
                                             skill: .reading, rating: 3, schedulerVersion: 99).validate())
    }

    func testImplausiblyLargeTimestampIsRejectedBeforeScheduling() {
        XCTAssertThrowsError(try review(time: Date(timeIntervalSince1970: 1e100)).validate())
    }

    func testEmptyNoteAndBookmarkFalseActAsTombstones() throws {
        let create = LearningEvent(deviceID: deviceA, timestamp: now, kind: .note, targetID: "v0001", value: "旧笔记")
        let clear = LearningEvent(deviceID: deviceB, timestamp: now.addingTimeInterval(5), kind: .note, targetID: "v0001", value: "")
        let add = LearningEvent(deviceID: deviceA, timestamp: now, kind: .bookmark, targetID: "v0001", value: "true")
        let remove = LearningEvent(deviceID: deviceB, timestamp: now.addingTimeInterval(5), kind: .bookmark, targetID: "v0001", value: "false")
        let snapshot = LearningSnapshot(events: try EventMerge.merge([clear, remove], [create, add]))
        XCTAssertEqual(snapshot.note("v0001"), "")
        XCTAssertFalse(snapshot.isBookmarked("v0001"))
    }

    func testArchiveRoundTripPreservesExactEventIdentity() throws {
        let event = review(time: Date(timeIntervalSince1970: 1_800_000_000.123456))
        let bytes = try ArchiveCodec.encode(ExchangeArchive(events: [event], contentVersion: "test"))
        let decoded = try ArchiveCodec.decode(bytes)
        XCTAssertEqual(decoded.events, [event])
        XCTAssertEqual(try EventMerge.merge([event], decoded.events).count, 1)
    }

    func testArchiveRejectsTruncationAndTampering() throws {
        let bytes = try ArchiveCodec.encode(ExchangeArchive(events: [review()], contentVersion: "test"))
        XCTAssertThrowsError(try ArchiveCodec.decode(Data(bytes.dropLast(5))))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["checksum"] = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try ArchiveCodec.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testFutureArchiveVersionIsNotSilentlyImported() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:
            ExchangeArchive(events: [], contentVersion: "test").encoded()) as? [String: Any])
        object["schemaVersion"] = 99
        XCTAssertThrowsError(try ExchangeArchive.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testKanaNormalizationKeepsDistinctLongVowelsDistinct() {
        XCTAssertTrue(AnswerChecker.matches(" ｶﾞｯｺｳ ", reading: "がっこう"))
        XCTAssertTrue(AnswerChecker.matches("ガッコウ", reading: "がっこう"))
        XCTAssertFalse(AnswerChecker.matches("がっこお", reading: "がっこう"))
        XCTAssertFalse(AnswerChecker.matches("がっこー", reading: "がっこう"))
        XCTAssertFalse(AnswerChecker.matches("", reading: ""))
    }

    func testCheckpointRecoversAnswerCommittedBeforePositionSaved() {
        var checkpoint = SessionCheckpoint(tasks: [.recall(ReviewKey(itemID: "v0001", skill: .reading)), .reading("r001")])
        let firstID = checkpoint.entries[0].id
        checkpoint.recover(recordedIDs: [firstID])
        XCTAssertEqual(checkpoint.index, 1)
        XCTAssertEqual(checkpoint.current?.id, checkpoint.entries[1].id)
    }

    func testCheckpointIsPortableAcrossAppRelaunch() throws {
        let original = SessionCheckpoint(tasks: [.exercise("e001a"), .reading("r001")], lessonID: "l001")
        let bytes = try ExchangeCoding.encoder().encode(original)
        let restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self, from: bytes)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.current?.id, original.current?.id)
        XCTAssertEqual(restored.lessonID, "l001")
        XCTAssertNoThrow(try restored.validate())
    }

    func testOutOfBoundsCheckpointDoesNotPretendLessonIsFinished() {
        var checkpoint = SessionCheckpoint(tasks: [.exercise("e001a")], lessonID: "l001")
        checkpoint.index = 500
        XCTAssertThrowsError(try checkpoint.validate())
    }

    func testHintUsageSurvivesPausingBeforeAnAnswerIsCommitted() throws {
        var original = SessionCheckpoint(tasks: [.exercise("e001a")])
        original.assistedEntryIDs.insert(original.entries[0].id)
        let restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self,
            from: ExchangeCoding.encoder().encode(original))
        try restored.validate()
        XCTAssertTrue(restored.assistedEntryIDs.contains(try XCTUnwrap(restored.current).id))
    }

    func testGrammarReviewRotatesSentenceContexts() throws {
        let pack = try ContentPack.bundled()
        let history = [review("g001", skill: .grammar, grade: 1, time: now.addingTimeInterval(-86400))]
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 20, now: now, newWordLimit: 5)
        guard let first = tasks.first, case .exercise(let id) = first else { return XCTFail("Expected grammar review") }
        XCTAssertEqual(id, "e001b")
    }

    func testDailyNewWordQuotaSurvivesStartingAnotherSession() throws {
        let pack = try ContentPack.bundled()
        let history = (1...5).flatMap { n in
            [review(String(format: "v%04d", n)), review(String(format: "v%04d", n), skill: .meaning)]
        }
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 20, now: now, newWordLimit: 5)
        let recallIDs = tasks.compactMap { task -> String? in
            if case .recall(let key) = task { return key.itemID }; return nil
        }
        XCTAssertTrue(recallIDs.allSatisfy { Int($0.dropFirst())! <= 5 })
    }

    func testLargeReviewQueueRespectsBudgetWithoutUnpreparedReading() throws {
        let pack = try ContentPack.bundled()
        let history = (1...30).map { review(String(format: "v%04d", $0), grade: 1, time: now.addingTimeInterval(-86400)) }
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 5, now: now)
        XCTAssertEqual(tasks.count, 10)
        XCTAssertFalse(tasks.contains { if case .reading = $0 { return true }; return false }, "Unprepared readings must not be forced into a full review queue")
        let unseen = tasks.compactMap { task -> String? in if case .recall(let key) = task { return key.itemID }; return nil }
        XCTAssertTrue(unseen.allSatisfy { Int($0.dropFirst())! <= 30 })
    }

    func testDailyCountsRespectLocalCalendarBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let midnight = calendar.startOfDay(for: now)
        let snapshot = LearningSnapshot(events: [review(time: midnight.addingTimeInterval(-1)), review(time: midnight.addingTimeInterval(1))])
        XCTAssertEqual(snapshot.reviewedToday(at: midnight.addingTimeInterval(60), calendar: calendar), 1)
    }
}
