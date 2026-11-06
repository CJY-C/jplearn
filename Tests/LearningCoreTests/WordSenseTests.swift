import XCTest
@testable import LearningCore

final class WordSenseTests: XCTestCase {
    func testRememberingOneMeaningDoesNotPrepareAnotherMeaningOfTheSameWord() throws {
        let pack = try ContentPack.bundled()
        let root = try XCTUnwrap(pack.item("vn6125"))
        let sound = try XCTUnwrap(pack.item("vn4962"))
        XCTAssertTrue(root.isLexeme)
        XCTAssertFalse(sound.isLexeme)
        XCTAssertEqual(sound.skills, [.meaning])
        XCTAssertEqual(sound.readingOwnerID, root.id)
        let passage = ReadingPassage(id: "sense-check", title: "用法", genre: "测试", level: "N4",
            sentenceIDs: ["svn4962a"], question: "词义", choices: ["甲", "乙"], answerIndex: 0,
            explanation: "测试", vocabulary: [ReadingWord(text: sound.text, itemID: sound.id)], grammarIDs: [])
        let oldMeaning = LearningEvent(deviceID: UUID(), kind: .review, targetID: root.id, skill: .meaning, rating: 4)
        let pronunciation = LearningEvent(deviceID: UUID(), kind: .review, targetID: root.id, skill: .reading, rating: 4)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: [oldMeaning, pronunciation]).knownOccurrences, 0)
        let newMeaning = LearningEvent(deviceID: UUID(), kind: .review, targetID: sound.id, skill: .meaning, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: [oldMeaning, pronunciation, newMeaning]).knownOccurrences, 1)
        XCTAssertEqual(pack.wordCount, Set(pack.items.filter { $0.kind == "word" }.map { $0.lexemeID ?? $0.id }).count)
    }

    func testIntroducingAnotherMeaningDoesNotRepeatItsSharedPronunciation() throws {
        let pack = try ContentPack.bundled(), now = Date()
        let history = pack.items.filter { $0.id != "vn4962" }.flatMap { item in item.skills.map {
            LearningEvent(deviceID: UUID(), timestamp: now.addingTimeInterval(-86_400), kind: .review,
                targetID: item.id, skill: $0, rating: 4)
        } }
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 5, now: now,
                                           newWordLimit: 5, newGrammarLimit: 0)
        let keys = tasks.compactMap { task -> ReviewKey? in
            if case .recall(let key) = task { return key }; return nil
        }
        XCTAssertTrue(keys.contains(ReviewKey(itemID: "vn4962", skill: .meaning)))
        XCTAssertFalse(keys.contains(ReviewKey(itemID: "vn4962", skill: .reading)))
    }

    func testLegacyWordsKeepTheirSkillsAndInvalidSenseLinksAreRejected() throws {
        let pack = try ContentPack.bundled()
        XCTAssertEqual(pack.item("v0001")?.skills, [.reading, .meaning])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any])
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        let index = try XCTUnwrap(items.firstIndex { $0["id"] as? String == "vn4962" })
        items[index]["lexemeID"] = "vn4963"
        json["items"] = items
        let invalid = try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try invalid.validate())
    }
}
