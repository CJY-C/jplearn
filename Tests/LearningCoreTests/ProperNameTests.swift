import XCTest
@testable import LearningCore

final class ProperNameTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let pack = try ContentPack.bundled()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any])
        var readings = try XCTUnwrap(json["readings"] as? [[String: Any]])
        let name: [String: Any] = ["text": "ミオ", "itemID": NSNull(), "properName": true]
        readings[0]["level"] = "N3"
        readings[0]["properNames"] = ["ミオ"]
        readings[0]["vocabulary"] = Array(repeating: name, count: 4)
        readings[0]["grammarIDs"] = []
        readings[0]["paragraphs"] = [["sentenceIDs": readings[0]["sentenceIDs"]!,
                                       "vocabulary": Array(repeating: name, count: 4)]]
        json["readings"] = readings
        return json
    }

    private func decode(_ json: [String: Any]) throws -> ContentPack {
        try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testLegacyPackWithoutNameFieldsStillDecodesAndValidates() throws {
        let pack = try ContentPack.bundled()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any])
        // These fields were absent in previously released packs.
        let readings = (json["readings"] as! [[String: Any]]).filter { $0["properNames"] == nil }
        XCTAssertFalse(readings.isEmpty)
        let data = try JSONSerialization.data(withJSONObject: readings[0])
        let legacy = try JSONDecoder().decode(ReadingPassage.self, from: data)
        XCTAssertNil(legacy.properNames)
        XCTAssertTrue((legacy.vocabulary ?? []).allSatisfy { $0.properName == nil })
        try decode(json).validate()
    }

    func testDeclaredNamesRemainUnknownOccurrencesAndOneDistinctWord() throws {
        let pack = try decode(fixture())
        try pack.validate()
        let reading = try XCTUnwrap(pack.readings.first)
        let reviews = pack.items.map { item in
            LearningEvent(deviceID: UUID(), kind: .review, targetID: item.id,
                skill: item.kind == "word" ? .meaning : .grammar, rating: 4)
        }
        let ready = ReadingReadiness.assess(reading, pack: pack, events: reviews)
        XCTAssertEqual(ready.totalOccurrences, 4)
        XCTAssertEqual(ready.knownOccurrences, 0)
        XCTAssertEqual(ready.unfamiliarWords.map(\.text), ["ミオ"])
        XCTAssertEqual(ready.maximumParagraphUnknown, 1)
        XCTAssertEqual(ready.coverage, 0)
        XCTAssertFalse(ready.isEligible)
    }

    func testNamesRequireUniqueUsedDeclarationsAndCannotHideAKnownItem() throws {
        for change in [["properNames": NSNull()], ["properNames": ["ミオ", "ミオ"]],
                       ["properNames": ["ミオ", "余分"]], ["properNames": [" "]]] as [[String: Any]] {
            var json = try fixture()
            var readings = json["readings"] as! [[String: Any]]
            readings[0].merge(change) { _, new in new }
            json["readings"] = readings
            XCTAssertThrowsError(try decode(json).validate())
        }
        var json = try fixture()
        var readings = json["readings"] as! [[String: Any]]
        var words = readings[0]["vocabulary"] as! [[String: Any]]
        words[0]["itemID"] = try XCTUnwrap(decode(json).items.first { $0.kind == "word" }).id
        readings[0]["vocabulary"] = words
        readings[0]["paragraphs"] = [["sentenceIDs": readings[0]["sentenceIDs"]!, "vocabulary": words]]
        json["readings"] = readings
        XCTAssertThrowsError(try decode(json).validate())
    }

    func testUnknownContentWordCannotBorrowTheAdvancedNameException() throws {
        var json = try fixture()
        var readings = json["readings"] as! [[String: Any]]
        readings[0].removeValue(forKey: "properNames")
        let words: [[String: Any]] = [["text": "未学習語", "itemID": NSNull()]]
        readings[0]["vocabulary"] = words
        readings[0]["paragraphs"] = [["sentenceIDs": readings[0]["sentenceIDs"]!, "vocabulary": words]]
        for level in ["N3", "N2"] {
            readings[0]["level"] = level
            json["readings"] = readings
            XCTAssertThrowsError(try decode(json).validate())
        }
        // Older beginner readings keep their explicit unknown vocabulary.
        readings[0]["level"] = "N5"
        json["readings"] = readings
        try decode(json).validate()
    }
}
