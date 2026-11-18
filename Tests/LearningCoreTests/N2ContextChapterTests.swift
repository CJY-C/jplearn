import XCTest
@testable import LearningCore

final class N2ContextChapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let device = UUID()

    func testEarlierSensesHaveIndependentMeaningsAndCorrectReadingSharing() throws {
        let pack = try ContentPack.bundled()
        let narrative = try XCTUnwrap(pack.item("vn3p002"))
        let trace = try XCTUnwrap(pack.item("vn3p005"))
        XCTAssertEqual(narrative.level, "N3")
        XCTAssertEqual(narrative.reading, "えがく")
        XCTAssertNil(narrative.readingOwnerID)
        XCTAssertEqual(narrative.skills, [.reading, .meaning])
        XCTAssertEqual(trace.readingOwnerID, "vn5035")
        XCTAssertEqual(trace.skills, [.meaning])
        for id in ["vn4s006", "vn4s007"] {
            XCTAssertEqual(pack.item(id)?.level, "N4")
            XCTAssertEqual(pack.item(id)?.readingOwnerID, "v0041")
            XCTAssertEqual(pack.item(id)?.skills, [.meaning])
        }
    }

    func testRememberingPaintAndItsReadingCannotProveNarrativeOrTraceMeaning() throws {
        let pack = try ContentPack.bundled(), original = pack.readings[0]
        let passage = ReadingPassage(id: "depiction", title: "描く", genre: "用法", level: "N3",
            sentenceIDs: original.sentenceIDs, question: original.question, choices: original.choices,
            answerIndex: original.answerIndex, explanation: original.explanation,
            vocabulary: [ReadingWord(text: "描く", itemID: "vn3p002"), ReadingWord(text: "描く", itemID: "vn3p005")], grammarIDs: [])
        let history = [Skill.reading, .meaning].map {
            LearningEvent(deviceID: device, timestamp: now, kind: .review, targetID: "vn5035", skill: $0, rating: 4)
        }
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history).knownOccurrences, 0)
        let own = LearningEvent(deviceID: device, timestamp: now, kind: .review, targetID: "vn3p002", skill: .meaning, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history + [own]).knownOccurrences, 1)
    }

    func testActualCalendarReadingRequiresRuleAndExceptionEvenWithCompleteVocabulary() throws {
        let pack = try ContentPack.bundled()
        let reading = try XCTUnwrap(pack.readings.first { $0.id == "rn2002" })
        var history = pack.items.flatMap { item in item.skills.map {
            LearningEvent(deviceID: device, timestamp: now, kind: .review, targetID: item.id, skill: $0, rating: 3)
        } }
        func readiness() -> ReadingReadiness {
            ReadingReadiness.assess(reading, pack: pack, knowledge: ReadingKnowledge(pack: pack, events: history, now: now))
        }
        XCTAssertEqual(readiness().percentage, 100)
        XCTAssertEqual(readiness().missingRuleIDs, ["rulemonth"])
        XCTAssertFalse(readiness().isEligible)
        let rule = try XCTUnwrap(pack.learningRules?.first { $0.id == "rulemonth" })
        for (index, set) in rule.practiceSets.enumerated() {
            let context = UUID().uuidString
            let time = now.addingTimeInterval(Double(index - 2) * 86_400)
            history += set.questions.map { LearningEvent(deviceID: device, timestamp: time, kind: .questionAttempt,
                targetID: $0.id, value: String($0.answerIndex), contextID: context, correct: true) }
            history.append(LearningEvent(deviceID: device, timestamp: time, kind: .placement,
                targetID: set.id, value: "passed", contextID: context))
        }
        XCTAssertTrue(readiness().isEligible)
        XCTAssertTrue(SessionPlanner.readingAvailable(reading, pack: pack, events: history, now: now))
        let resetAt = now.addingTimeInterval(1)
        let set = rule.practiceSets[0], context = UUID().uuidString
        history += set.questions.map { LearningEvent(deviceID: device, timestamp: resetAt, kind: .questionAttempt,
            targetID: $0.id, value: String(($0.answerIndex + 1) % $0.choices.count), contextID: context, correct: false) }
        history.append(LearningEvent(deviceID: device, timestamp: resetAt, kind: .placement,
            targetID: set.id, value: "review", contextID: context))
        XCTAssertFalse(SessionPlanner.readingAvailable(reading, pack: pack, events: history, now: resetAt))
    }
}
