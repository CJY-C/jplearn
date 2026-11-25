import XCTest
@testable import LearningCore

final class DialogueBridgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func history(_ passage: ReadingPassage, excluding: Set<String> = [],
                         wordSkill: Skill = .meaning) -> [LearningEvent] {
        Set((passage.vocabulary ?? []).compactMap(\.itemID)).filter { !excluding.contains($0) }.map {
            LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
                targetID: $0, skill: wordSkill, rating: 3)
        } + (passage.grammarIDs ?? []).filter { !excluding.contains($0) }.map {
            LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
                targetID: $0, skill: .grammar, rating: 3)
        }
    }

    func testActualDialogueNeedsIndependentEllipsisRecallAlongsideWordMeanings() throws {
        let pack = try ContentPack.bundled()
        let passage = try XCTUnwrap(pack.readings.first { $0.id == "rnbd001" })
        let events = history(passage, excluding: ["g019"])
        let missing = ReadingReadiness.assess(passage, pack: pack, events: events)
        XCTAssertEqual(missing.percentage, 100)
        XCTAssertEqual(missing.missingGrammarIDs, ["g019"])
        XCTAssertFalse(missing.isEligible)
        let hint = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "g019", skill: .grammar, rating: 3, assisted: true)
        XCTAssertFalse(ReadingReadiness.assess(passage, pack: pack, events: events + [hint]).isEligible)
        let recall = LearningEvent(deviceID: UUID(), timestamp: now.addingTimeInterval(1), kind: .review,
            targetID: "g019", skill: .grammar, rating: 3)
        XCTAssertTrue(ReadingReadiness.assess(passage, pack: pack, events: events + [hint, recall]).isEligible)
    }

    func testKnownOverallWordsCannotHideTooManyUnknownsInOneDialogueParagraph() throws {
        let pack = try ContentPack.bundled()
        let passage = try XCTUnwrap(pack.readings.first { $0.id == "rnbd001" })
        let paragraphs = try XCTUnwrap(passage.paragraphs)
        let counts = Dictionary(grouping: passage.vocabulary ?? [], by: { $0.itemID ?? "" }).mapValues(\.count)
        let later = Set(paragraphs.dropFirst().flatMap { $0.vocabulary }.compactMap(\.itemID))
        let candidates = Set(paragraphs[0].vocabulary.compactMap(\.itemID)).filter {
            counts[$0] == 1 && !later.contains($0)
        }.sorted()
        XCTAssertGreaterThanOrEqual(candidates.count, 4)
        let unknown = Set(candidates.prefix(4))
        let events = history(passage, excluding: unknown)
        let concentrated = ReadingReadiness.assess(passage, pack: pack, events: events)
        XCTAssertGreaterThanOrEqual(concentrated.coverage, 0.95)
        XCTAssertEqual(concentrated.maximumParagraphUnknown, 4)
        XCTAssertFalse(concentrated.isEligible)
        let extra = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: try XCTUnwrap(unknown.sorted().first), skill: .meaning, rating: 3)
        let ready = ReadingReadiness.assess(passage, pack: pack, events: events + [extra])
        XCTAssertEqual(ready.maximumParagraphUnknown, 3)
        XCTAssertTrue(ready.isEligible)
    }

    func testReadingTheKanaDoesNotPretendToUnderstandDialogueVocabulary() throws {
        let pack = try ContentPack.bundled()
        for id in ["rnbd001", "rnbd002", "rnbd003"] {
            let passage = try XCTUnwrap(pack.readings.first { $0.id == id })
            let result = ReadingReadiness.assess(passage, pack: pack, events: history(passage, wordSkill: .reading))
            XCTAssertEqual(result.percentage, 0)
            XCTAssertFalse(result.isEligible)
            XCTAssertTrue(ReadingReadiness.assess(passage, pack: pack, events: history(passage)).isEligible)
        }
    }

    func testAssessmentStaysOutOfOrdinaryRotationAndCompletedPracticeCoolsDown() throws {
        let pack = try ContentPack.bundled()
        let assessment = try XCTUnwrap(pack.readings.first { $0.id == "rnbd003" })
        let prepared = history(assessment)
        XCTAssertFalse(SessionPlanner.readingAvailable(assessment, pack: pack, events: prepared, now: now))
        XCTAssertTrue(SessionPlanner.readingAvailable(assessment, pack: pack, events: prepared,
            now: now, includeAssessments: true))
        for id in ["rnbd001", "rnbd002"] {
            let reading = try XCTUnwrap(pack.readings.first { $0.id == id })
            let known = history(reading)
            XCTAssertTrue(SessionPlanner.readingAvailable(reading, pack: pack, events: known, now: now))
            let completed = LearningEvent(deviceID: UUID(), timestamp: now, kind: .readingAttempt,
                targetID: id, value: "correct")
            XCTAssertFalse(SessionPlanner.readingAvailable(reading, pack: pack, events: known + [completed],
                now: now.addingTimeInterval(600)))
        }
    }
}
