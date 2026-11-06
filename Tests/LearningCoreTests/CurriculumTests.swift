import XCTest
@testable import LearningCore

final class CurriculumTests: XCTestCase {
    func testHeldOutReadingsNeverAppearInOrdinaryRounds() throws {
        let pack = try ContentPack.bundled(), now = Date()
        let history = pack.items.flatMap { item in item.skills.map {
            LearningEvent(deviceID: UUID(), timestamp: now, kind: .review, targetID: item.id, skill: $0, rating: 3)
        } }
        let heldOut = Set(pack.readings.filter { $0.purpose == "assessment" }.map(\.id))
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 20, now: now)
        for task in tasks {
            if case .reading(let id) = task { XCTAssertFalse(heldOut.contains(id)) }
        }
        XCTAssertGreaterThanOrEqual(heldOut.count, 20)
    }

    func testPreparedLearnerCanReadNewPracticeWithoutInventingUnknownWordMastery() throws {
        let pack = try ContentPack.bundled()
        let history = pack.items.flatMap { item in item.skills.map {
            LearningEvent(deviceID: UUID(), kind: .review, targetID: item.id, skill: $0, rating: 3)
        } }
        for reading in pack.readings where reading.id.hasPrefix("rn5") && reading.purpose == "practice" {
            XCTAssertTrue(ReadingReadiness.assess(reading, pack: pack, events: history).isEligible, reading.id)
        }
        let names = try XCTUnwrap(pack.readings.first { $0.id == "rn5042" })
        let readiness = ReadingReadiness.assess(names, pack: pack, events: history)
        XCTAssertLessThan(readiness.percentage, 100)
        XCTAssertTrue(readiness.unfamiliarWords.contains { $0.text == "森" && $0.itemID == nil })
    }

    func testLegacySingleQuestionAndCheckpointDecodeWithNewReader() throws {
        let pack = try ContentPack.bundled(), legacy = pack.readings[0]
        XCTAssertEqual(legacy.allQuestions.count, 1)
        XCTAssertEqual(legacy.allQuestions[0].prompt, legacy.question)
        let checkpoint = SessionCheckpoint(tasks: [.reading(legacy.id)])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: ExchangeCoding.encoder().encode(checkpoint)) as? [String: Any])
        json.removeValue(forKey: "questionIndex")
        let decoded = try ExchangeCoding.decoder().decode(SessionCheckpoint.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.questionIndex)
        XCTAssertEqual(decoded.current?.id, checkpoint.current?.id)
    }

    func testUnavailablePrerequisitePreventsNewGrammarButNotOtherStudy() throws {
        let pack = try ContentPack.bundled()
        let tasks = try SessionPlanner.make(pack: pack, events: [], minutes: 20)
        let ids = tasks.compactMap { if case .exercise(let id) = $0 { return pack.exercise(id)?.targetID }; return nil }
        XCTAssertFalse(ids.contains("g022"))
        XCTAssertFalse(tasks.isEmpty)
    }

    func testNewQuestionEventsAndPlacementSurviveMergeAndBackup() throws {
        let question = LearningEvent(deviceID: UUID(), kind: .questionAttempt, targetID: "r033q1", value: "0",
            contextID: UUID().uuidString, correct: true)
        let placement = LearningEvent(deviceID: UUID(), kind: .placement, targetID: "intro1", value: "passed")
        let merged = try EventMerge.merge([question], [question, placement])
        let archive = try ArchiveCodec.decode(ArchiveCodec.encode(ExchangeArchive(events: merged, contentVersion: "0.4.0")))
        XCTAssertEqual(archive.events, merged)
        XCTAssertEqual(merged.count, 2)
        XCTAssertThrowsError(try LearningEvent(deviceID: UUID(), kind: .questionAttempt, targetID: "q", value: "0").validate())
    }

    func testPerParagraphLimitReplacesGlobalLimitForLongReading() throws {
        let pack = try ContentPack.bundled(), base = pack.readings.first { $0.id == "r024" }!
        let known = ReadingWord(text: "今日", itemID: "v0001")
        let paragraphs = (0..<4).map { index in
            ReadingParagraph(sentenceIDs: [base.sentenceIDs[index]], vocabulary:
                Array(repeating: known, count: 24) + [ReadingWord(text: "未知\(index)", itemID: nil)])
        }
        var reading = base
        reading = ReadingPassage(id: "density", title: base.title, genre: base.genre, level: base.level,
            sentenceIDs: Array(base.sentenceIDs.prefix(4)), question: base.question, choices: base.choices,
            answerIndex: base.answerIndex, explanation: base.explanation,
            vocabulary: paragraphs.flatMap(\.vocabulary), grammarIDs: [], paragraphs: paragraphs)
        let history = [LearningEvent(deviceID: UUID(), kind: .review, targetID: "v0001", skill: .meaning, rating: 3)]
        let readiness = ReadingReadiness.assess(reading, pack: pack, events: history)
        XCTAssertEqual(readiness.unfamiliarWords.count, 4)
        XCTAssertEqual(readiness.maximumParagraphUnknown, 1)
        XCTAssertTrue(readiness.isEligible)
    }
}
