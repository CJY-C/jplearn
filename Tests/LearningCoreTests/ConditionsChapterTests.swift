import XCTest
@testable import LearningCore

final class ConditionsChapterTests: XCTestCase {
    func testSchedulingLaterNeedsItsOwnMeaningButSharesPhysicalRotationReading() throws {
        let pack = try ContentPack.bundled()
        let sense = try XCTUnwrap(pack.item("vn3s004")), root = try XCTUnwrap(pack.item("vn5766"))
        XCTAssertEqual(sense.lexemeID, root.id)
        XCTAssertEqual(sense.readingOwnerID, root.id)
        XCTAssertEqual(sense.skills, [.meaning])
        let passage = ReadingPassage(id: "postpone-sense", title: "回す", genre: "用法", level: "N3",
            sentenceIDs: sense.exampleSentenceIDs ?? [], question: "词义", choices: ["甲", "乙"], answerIndex: 0,
            explanation: "用法检查", vocabulary: [ReadingWord(text: sense.text, itemID: sense.id)], grammarIDs: [])
        let history = root.skills.map {
            LearningEvent(deviceID: UUID(), kind: .review, targetID: root.id, skill: $0, rating: 3)
        }
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history).knownOccurrences, 0)
        let own = LearningEvent(deviceID: UUID(), kind: .review, targetID: sense.id, skill: .meaning, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history + [own]).knownOccurrences, 1)
    }

    func testSchedulingLaterDoesNotScheduleADuplicateReadingCard() throws {
        let pack = try ContentPack.bundled(), now = Date()
        let history = pack.items.filter { $0.id != "vn3s004" }.flatMap { item in item.skills.map {
            LearningEvent(deviceID: UUID(), timestamp: now.addingTimeInterval(-86_400), kind: .review,
                targetID: item.id, skill: $0, rating: 4)
        } }
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 5, now: now,
                                           newWordLimit: 5, newGrammarLimit: 0)
        let keys = tasks.compactMap { task -> ReviewKey? in
            if case .recall(let key) = task { return key }; return nil
        }
        XCTAssertTrue(keys.contains(ReviewKey(itemID: "vn3s004", skill: .meaning)))
        XCTAssertFalse(keys.contains(ReviewKey(itemID: "vn3s004", skill: .reading)))
    }

    func testActualConsultationPassageNeedsBothConditionalFunctions() throws {
        let pack = try ContentPack.bundled(), now = Date()
        let passage = try XCTUnwrap(pack.readings.first { $0.id == "rn2204" })
        let history = pack.items.filter { !["gn2c006", "gn2c007"].contains($0.id) }.flatMap { item in item.skills.map {
            LearningEvent(deviceID: UUID(), timestamp: now, kind: .review, targetID: item.id, skill: $0, rating: 3)
        } }
        let readiness = ReadingReadiness.assess(passage, pack: pack, events: history)
        XCTAssertEqual(readiness.percentage, 100)
        XCTAssertEqual(Set(readiness.missingGrammarIDs), Set(["gn2c006", "gn2c007"]))
        XCTAssertFalse(readiness.isEligible)
        let one = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "gn2c006", skill: .grammar, rating: 3)
        XCTAssertFalse(ReadingReadiness.assess(passage, pack: pack, events: history + [one]).isEligible)
        let both = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "gn2c007", skill: .grammar, rating: 3)
        XCTAssertTrue(ReadingReadiness.assess(passage, pack: pack, events: history + [one, both]).isEligible)
    }
}
