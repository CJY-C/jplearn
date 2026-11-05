import XCTest
@testable import LearningCore

final class SessionPlanningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let device = UUID()

    private func review(_ id: String, _ skill: Skill = .meaning, grade: Int = 3,
                        assisted: Bool = false, time: Date? = nil) -> LearningEvent {
        LearningEvent(deviceID: device, timestamp: time ?? now, kind: .review,
                      targetID: id, skill: skill, rating: grade, assisted: assisted)
    }
    private func prepared(_ pack: ContentPack) -> [LearningEvent] {
        pack.items.flatMap { item in item.skills.map { review(item.id, $0) } }
    }
    private func attempt(_ id: String, time: Date? = nil) -> LearningEvent {
        LearningEvent(deviceID: device, timestamp: time ?? now, kind: .readingAttempt,
                      targetID: id, value: "correct")
    }
    private func readingIDs(_ tasks: [SessionTask]) -> [String] {
        tasks.compactMap { if case .reading(let id) = $0 { return id }; return nil }
    }
    private func sample(_ words: [ReadingWord], long: Bool = false) throws -> (ContentPack, ReadingPassage) {
        let pack = try ContentPack.bundled()
        let original = pack.readings.first { $0.id == (long ? "r024" : "r007") }!
        let reading = ReadingPassage(id: "coverage-test", title: original.title, genre: original.genre,
            level: original.level, sentenceIDs: original.sentenceIDs, question: original.question,
            choices: original.choices, answerIndex: original.answerIndex, explanation: original.explanation,
            vocabulary: words, grammarIDs: [])
        return (pack, reading)
    }

    func testExhaustedContentDoesNotLoopBackToLibraryReading() throws {
        let pack = try ContentPack.bundled()
        let history = prepared(pack) + pack.readings.map { attempt($0.id) }
        for minute in [9, 10, 20, 60] {
            let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: minute, now: now)
            XCTAssertTrue(tasks.isEmpty, "A time goal must not cause r001 to repeat")
        }
    }

    func testSubsequentRoundsChooseDifferentPreparedReadingsUntilExhausted() throws {
        let pack = try ContentPack.bundled()
        var history = prepared(pack)
        var seen = Set<String>()
        let practiceReadings = pack.readings.filter { $0.purpose != "assessment" }
        for _ in practiceReadings {
            let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 20, now: now)
            let id = try XCTUnwrap(readingIDs(tasks).first)
            XCTAssertTrue(seen.insert(id).inserted)
            history.append(attempt(id))
        }
        XCTAssertEqual(seen.count, practiceReadings.count)
        XCTAssertTrue(try SessionPlanner.make(pack: pack, events: history, minutes: 20, now: now).isEmpty)
    }

    func testReadingDoesNotRepeatAtMidnightButCanReturnAfterSpacing() throws {
        let pack = try ContentPack.bundled(), reading = pack.readings[0]
        let history = prepared(pack) + [attempt(reading.id)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tomorrow = calendar.startOfDay(for: now).addingTimeInterval(86_400 + 1)
        XCTAssertFalse(SessionPlanner.readingAvailable(reading, pack: pack, events: history, now: tomorrow, calendar: calendar))
        XCTAssertTrue(SessionPlanner.readingAvailable(reading, pack: pack, events: history,
                                                      now: now.addingTimeInterval(86_401), calendar: calendar))
    }

    func testUnpreparedReadingsAreNotScheduledEvenIfUnseen() throws {
        let pack = try ContentPack.bundled()
        let tasks = try SessionPlanner.make(pack: pack, events: [], minutes: 20, now: now)
        XCTAssertTrue(readingIDs(tasks).isEmpty)
        XCTAssertEqual(Set(tasks.map(\.id)).count, tasks.count)
    }

    func testNewWordSkillsAreSeparatedAndRespectConfiguredQuota() throws {
        let pack = try ContentPack.bundled()
        let tasks = try SessionPlanner.make(pack: pack, events: [], minutes: 20, now: now, newWordLimit: 5)
        let words = tasks.compactMap { task -> ReviewKey? in if case .recall(let key) = task { return key }; return nil }
        XCTAssertEqual(Set(words.map(\.itemID)).count, 5)
        XCTAssertEqual(words.count, 10)
        for pair in zip(words, words.dropFirst()) { XCTAssertNotEqual(pair.0.itemID, pair.1.itemID) }
    }

    func testCoverageCountsOccurrencesInsteadOfDistinctWords() throws {
        let words = Array(repeating: ReadingWord(text: "今日", itemID: "v0001"), count: 9) +
            [ReadingWord(text: "朝", itemID: "v0005")]
        let (pack, reading) = try sample(words)
        let assessment = ReadingReadiness.assess(reading, pack: pack, events: [review("v0001")])
        XCTAssertEqual(assessment.knownOccurrences, 9)
        XCTAssertEqual(assessment.totalOccurrences, 10)
        XCTAssertEqual(assessment.percentage, 90)
        XCTAssertEqual(assessment.unfamiliarWords.count, 1)
    }

    func testPronunciationHintsAndFailedMeaningDoNotCountAsKnown() throws {
        let (pack, reading) = try sample([ReadingWord(text: "今日", itemID: "v0001")])
        for events in [[review("v0001", .reading)], [review("v0001", grade: 4, assisted: true)],
                       [review("v0001"), review("v0001", grade: 1, time: now.addingTimeInterval(1))]] {
            XCTAssertEqual(ReadingReadiness.assess(reading, pack: pack, events: events).knownOccurrences, 0)
        }
    }

    func testLongReadingRequires95PercentAndShortReadingAllows80Percent() throws {
        let known = ReadingWord(text: "今日", itemID: "v0001"), unknown = ReadingWord(text: "朝", itemID: "v0005")
        let words = Array(repeating: known, count: 18) + Array(repeating: unknown, count: 2)
        let (pack, short) = try sample(words)
        let (_, long) = try sample(words, long: true)
        let history = [review("v0001")]
        XCTAssertTrue(ReadingReadiness.assess(short, pack: pack, events: history).isEligible)
        XCTAssertFalse(ReadingReadiness.assess(long, pack: pack, events: history).isEligible)
        let (_, readyLong) = try sample(Array(repeating: known, count: 19) + [unknown], long: true)
        XCTAssertTrue(ReadingReadiness.assess(readyLong, pack: pack, events: history).isEligible)
    }

    func testOutsideDictionaryWordsAreNotSilentlyTreatedAsKnown() throws {
        let (pack, reading) = try sample([ReadingWord(text: "未收录词", itemID: nil)])
        let result = ReadingReadiness.assess(reading, pack: pack, events: prepared(pack))
        XCTAssertEqual(result.knownOccurrences, 0)
        XCTAssertFalse(result.isEligible)
    }

    func testHighCoverageStillRequiresPrerequisiteGrammar() throws {
        let pack = try ContentPack.bundled(), reading = pack.readings[0]
        let wordsOnly = prepared(pack).filter { $0.skill != .grammar }
        let result = ReadingReadiness.assess(reading, pack: pack, events: wordsOnly)
        XCTAssertEqual(result.percentage, 100)
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(Set(result.missingGrammarIDs), Set(reading.grammarIDs!))
    }

    func testExpandedLongReadingsCanBeUnlockedByBundledCurriculum() throws {
        let pack = try ContentPack.bundled()
        for reading in pack.readings {
            let readiness = ReadingReadiness.assess(reading, pack: pack, events: prepared(pack))
            XCTAssertTrue(readiness.isEligible, reading.id)
            XCTAssertEqual(readiness.percentage, 100)
        }
    }

    func testOldCheckpointRemovesDuplicateReadingAndPreservesOtherProgress() throws {
        let pack = try ContentPack.bundled()
        var checkpoint = SessionCheckpoint(tasks: [.exercise("e001a"), .reading("r001"), .exercise("e002a")])
        checkpoint.index = 1
        checkpoint.assistedEntryIDs.insert(checkpoint.entries[1].id)
        checkpoint.removeUnavailableReadings(pack: pack, events: prepared(pack) + [attempt("r001")], now: now)
        XCTAssertEqual(checkpoint.index, 1)
        XCTAssertEqual(checkpoint.current?.task.id, "exercise:e002a")
        XCTAssertTrue(checkpoint.assistedEntryIDs.isEmpty)
        XCTAssertNoThrow(try checkpoint.validate())
    }
}
