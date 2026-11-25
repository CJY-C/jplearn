import XCTest
@testable import LearningCore

final class ChangeAndScopeTests: XCTestCase {
    func testSelectedReadingsStayWithinTheirMeaningAndWrittenForm() throws {
        let pack = try ContentPack.bundled()
        let abstract = try XCTUnwrap(pack.item("vn3u015"))
        XCTAssertEqual(abstract.lexemeID, "vn4854")
        XCTAssertNil(abstract.readingOwnerID)
        XCTAssertEqual(abstract.skills, [.reading, .meaning])
        for (id, accepted, rejected) in [
            ("vn3u015", ["いだく"], ["だく"]),
            ("vn3u011", ["いちば"], ["しじょう"]),
            ("vn3u013", ["ぶん"], ["ふん", "ぶ"]),
            ("vn2h009", ["かきとめる", "かきとどめる"], [])
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

    func testNovelDiscussionCoverageNeedsAbstractMeaningRatherThanBodyOrReading() throws {
        let pack = try ContentPack.bundled(), now = Date()
        let passage = try XCTUnwrap(pack.readings.first { $0.id == "rn2305" })
        let words = Set((passage.vocabulary ?? []).compactMap(\.itemID))
        let history = words.filter { $0 != "vn3u015" }.map {
            LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
                targetID: $0, skill: .meaning, rating: 3)
        } + [LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "vn4854", skill: .meaning, rating: 3)]
        let before = ReadingReadiness.assess(passage, pack: pack, events: history)
        XCTAssertTrue(before.isLong)
        XCTAssertEqual(Set(before.unfamiliarWords.compactMap(\.itemID)), Set(["vn3u015"]))
        let readingOnly = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "vn3u015", skill: .reading, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history + [readingOnly]).knownOccurrences,
                       before.knownOccurrences)
        let meaning = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "vn3u015", skill: .meaning, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history + [meaning]).percentage, 100)
    }

    func testActualReceptionPassageRequiresBothChangeAndAdaptationFunctions() throws {
        let pack = try ContentPack.bundled(), now = Date()
        let passage = try XCTUnwrap(pack.readings.first { $0.id == "rn2301" })
        let vocabulary = Set((passage.vocabulary ?? []).compactMap(\.itemID))
        let history = vocabulary.map {
            LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
                targetID: $0, skill: .meaning, rating: 3)
        } + (passage.grammarIDs ?? []).filter { !["gn2d001", "gn2d002"].contains($0) }.map {
            LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
                targetID: $0, skill: .grammar, rating: 3)
        }
        let missing = ReadingReadiness.assess(passage, pack: pack, events: history)
        XCTAssertEqual(missing.percentage, 100)
        XCTAssertEqual(Set(missing.missingGrammarIDs), Set(["gn2d001", "gn2d002"]))
        XCTAssertFalse(missing.isEligible)
        let one = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "gn2d001", skill: .grammar, rating: 3)
        let assisted = LearningEvent(deviceID: UUID(), timestamp: now, kind: .review,
            targetID: "gn2d002", skill: .grammar, rating: 3, assisted: true)
        XCTAssertFalse(ReadingReadiness.assess(passage, pack: pack, events: history + [one, assisted]).isEligible)
        let second = LearningEvent(deviceID: UUID(), timestamp: now.addingTimeInterval(1), kind: .review,
            targetID: "gn2d002", skill: .grammar, rating: 3)
        XCTAssertTrue(ReadingReadiness.assess(passage, pack: pack, events: history + [one, second]).isEligible)
    }
}
