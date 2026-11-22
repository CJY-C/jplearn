import XCTest
@testable import LearningCore

final class SimilarityChapterTests: XCTestCase {
    func testPreparedReaderStillHasFourUnknownNameOccurrences() throws {
        let pack = try ContentPack.bundled()
        let reviews = pack.items.map { item in
            LearningEvent(deviceID: UUID(), kind: .review, targetID: item.id,
                skill: item.kind == "word" ? .meaning : .grammar, rating: 4)
        }
        let knowledge = ReadingKnowledge(events: reviews)
        let readings = pack.readings.filter { (3111...3130).contains(Int($0.id.dropFirst(2)) ?? 0) && $0.id.hasPrefix("rn") }
        XCTAssertEqual(readings.count, 20)
        for reading in readings {
            let ready = ReadingReadiness.assess(reading, pack: pack, knowledge: knowledge)
            XCTAssertTrue(ready.isEligible, reading.id)
            if reading.id == "rn3130" {
                XCTAssertEqual(reading.properNames, ["ミオ"])
                XCTAssertEqual(ready.totalOccurrences - ready.knownOccurrences, 4)
                XCTAssertEqual(ready.unfamiliarWords.map(\.text), ["ミオ"])
                XCTAssertEqual(ready.maximumParagraphUnknown, 1)
                XCTAssertLessThan(ready.coverage, 1)
            } else {
                XCTAssertEqual(ready.coverage, 1, reading.id)
            }
        }
    }

    func testCollisionAndPredictionReviewsDoNotPrepareTheSunlightSense() throws {
        let pack = try ContentPack.bundled()
        let sense = try XCTUnwrap(pack.item("vn3l124"))
        let reading = ReadingPassage(id: "light-check", title: "受光", genre: "测试", level: "N3",
            sentenceIDs: ["svn3l124a"], question: "词义", choices: ["甲", "乙"], answerIndex: 0,
            explanation: "测试", vocabulary: [ReadingWord(text: sense.text, itemID: sense.id)], grammarIDs: [])
        let previous = ["vn3l025", "vn3l123"].map {
            LearningEvent(deviceID: UUID(), kind: .review, targetID: $0, skill: .meaning, rating: 4)
        }
        XCTAssertEqual(ReadingReadiness.assess(reading, pack: pack, events: previous).knownOccurrences, 0)
        let own = LearningEvent(deviceID: UUID(), kind: .review, targetID: sense.id, skill: .meaning, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(reading, pack: pack, events: previous + [own]).knownOccurrences, 1)
        XCTAssertEqual(sense.readingOwnerID, "vn3l025")
        XCTAssertEqual(sense.skills, [.meaning])
    }
}
