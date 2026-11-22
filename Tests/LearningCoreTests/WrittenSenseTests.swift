import XCTest
@testable import LearningCore

final class WrittenSenseTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let pack = try ContentPack.bundled()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any])
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        XCTAssertTrue(items.contains { $0["id"] as? String == "vn4q003" })
        return json
    }
    private func decode(_ json: [String: Any]) throws -> ContentPack {
        try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func testNewWrittenFormKeepsRootCountAndItsOwnReadingPractice() throws {
        let pack = try decode(fixture()); try pack.validate()
        let item = try XCTUnwrap(pack.item("vn4q003"))
        let wordTargets = pack.items.filter { $0.kind == "word" }
        XCTAssertEqual(pack.wordCount, wordTargets.count - wordTargets.filter { !$0.isLexeme }.count)
        for (id, ownerID) in [("vn4q001", "vn5246"), ("vn4q002", "vn5422"), ("vn4q003", "vn5036")] {
            let sense = try XCTUnwrap(pack.item(id)), owner = try XCTUnwrap(pack.item(ownerID))
            XCTAssertFalse(sense.isLexeme)
            XCTAssertEqual(sense.lexemeID, owner.id)
            XCTAssertEqual(sense.jmdictEntryID, owner.jmdictEntryID)
            XCTAssertNotEqual(sense.text, owner.text)
            XCTAssertNil(sense.readingOwnerID)
            XCTAssertEqual(sense.skills, [.reading, .meaning])
        }
        XCTAssertEqual(item.text, "録る")
        XCTAssertEqual(item.skills, [.reading, .meaning])
        XCTAssertNil(item.readingOwnerID)
        XCTAssertTrue(pack.hasSenseVariants(item))
        let passage = ReadingPassage(id: "test-passage", title: "录制", genre: "测试", level: "N3",
            sentenceIDs: ["svn4q003a"], question: "词义", choices: ["甲", "乙"], answerIndex: 0,
            explanation: "测试", vocabulary: [ReadingWord(text: item.text, itemID: item.id)], grammarIDs: [])
        let photo = LearningEvent(deviceID: UUID(), kind: .review, targetID: "vn5036", skill: .meaning, rating: 4)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: [photo]).knownOccurrences, 0)
        let recording = LearningEvent(deviceID: UUID(), kind: .review, targetID: item.id, skill: .meaning, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: [photo, recording]).knownOccurrences, 1)
    }
    func testDifferentSpellingCannotBorrowAnOldReadingReview() throws {
        var json = try fixture(); var items = json["items"] as! [[String: Any]]
        let index = try XCTUnwrap(items.firstIndex { $0["id"] as? String == "vn4q003" })
        items[index]["readingOwnerID"] = "vn5036"; json["items"] = items
        XCTAssertThrowsError(try decode(json).validate())
    }
    func testCrossSpellingRequiresSharedEntryAndSpecificSource() throws {
        for change in [["jmdictEntryID": 1], ["jmdictEntryID": 0], ["jmdictEntryID": NSNull()],
                       ["citations": []], ["sourceIDs": ["projectopen"]]] as [[String: Any]] {
            var json = try fixture(); var items = json["items"] as! [[String: Any]]
            let index = try XCTUnwrap(items.firstIndex { $0["id"] as? String == "vn4q003" })
            items[index].merge(change) { _, new in new }; json["items"] = items
            XCTAssertThrowsError(try decode(json).validate())
        }
    }
    func testAnotherSpellingDoesNotBecomeAnotherRoot() throws {
        var json = try fixture(); var items = json["items"] as! [[String: Any]]
        let index = try XCTUnwrap(items.firstIndex { $0["id"] as? String == "vn4q003" })
        items[index].removeValue(forKey: "lexemeID")
        items[index]["prerequisiteIDs"] = []; json["items"] = items
        XCTAssertThrowsError(try decode(json).validate())
    }
}
