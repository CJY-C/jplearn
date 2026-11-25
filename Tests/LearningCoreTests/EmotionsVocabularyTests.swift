import XCTest
@testable import LearningCore

final class EmotionsVocabularyTests: XCTestCase {
    func testKnowingNegativeScopeOrSarcasmCannotProveTheirOtherMeanings() throws {
        let pack = try ContentPack.bundled()
        for (rootID, senseID) in [("vn2g076", "vn2g077"), ("vn2g089", "vn2g090")] {
            let root = try XCTUnwrap(pack.item(rootID)), sense = try XCTUnwrap(pack.item(senseID))
            XCTAssertEqual(sense.readingOwnerID, root.id)
            XCTAssertEqual(sense.skills, [.meaning])
            let reading = ReadingPassage(id: "sense-" + sense.id, title: sense.text, genre: "用法", level: "N2",
                sentenceIDs: sense.exampleSentenceIDs ?? [], question: "词义", choices: ["甲", "乙"], answerIndex: 0,
                explanation: "词义区分", vocabulary: [ReadingWord(text: sense.text, itemID: sense.id)], grammarIDs: [])
            let history = root.skills.map {
                LearningEvent(deviceID: UUID(), kind: .review, targetID: root.id, skill: $0, rating: 3)
            }
            XCTAssertEqual(ReadingReadiness.assess(reading, pack: pack, events: history).knownOccurrences, 0)
            let own = LearningEvent(deviceID: UUID(), kind: .review, targetID: sense.id, skill: .meaning, rating: 3)
            XCTAssertEqual(ReadingReadiness.assess(reading, pack: pack, events: history + [own]).knownOccurrences, 1)
        }
    }

    func testAdditionalMeaningsScheduleWithoutDuplicateReadingCards() throws {
        let pack = try ContentPack.bundled(), now = Date(), extra = Set(["vn2g077", "vn2g090"])
        let history = pack.items.filter { !extra.contains($0.id) }.flatMap { item in item.skills.map {
            LearningEvent(deviceID: UUID(), timestamp: now.addingTimeInterval(-86_400), kind: .review,
                targetID: item.id, skill: $0, rating: 4)
        } }
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 5, now: now,
                                           newWordLimit: 5, newGrammarLimit: 0)
        let keys = tasks.compactMap { task -> ReviewKey? in
            if case .recall(let key) = task { return key }; return nil
        }
        for id in extra {
            XCTAssertTrue(keys.contains(ReviewKey(itemID: id, skill: .meaning)))
            XCTAssertFalse(keys.contains(ReviewKey(itemID: id, skill: .reading)))
        }
    }

    func testReadingsStayWithinTheDisplayedFormAndSelectedSense() throws {
        let pack = try ContentPack.bundled()
        for (id, accepted, rejected) in [
            ("vn2g026", ["めんどうくさい", "めんどくさい"], []),
            ("vn2g039", ["いばる", "えばる"], []),
            ("vn2g036", ["こらえる"], ["こたえる", "たえる"]),
            ("vn2g057", ["めした"], ["もっか"]),
            ("vn2g091", ["しゃれ"], ["しゃらく", "しゃら"]),
            ("vn2g095", ["しんしん"], ["しんじん"]),
            ("vn2g027", ["しつこい"], ["しつっこい"]),
            ("vn2g030", ["どきどき"], ["どきんどきん"]),
            ("vn2g078", ["あれこれ"], ["かれこれ", "ひし"])
        ] {
            let word = try XCTUnwrap(pack.item(id))
            for answer in accepted {
                XCTAssertTrue(AnswerChecker.matches(answer, reading: word.reading, alternatives: word.acceptedReadings ?? []), id)
            }
            for answer in rejected {
                XCTAssertFalse(AnswerChecker.matches(answer, reading: word.reading, alternatives: word.acceptedReadings ?? []), id)
            }
        }
    }
}
