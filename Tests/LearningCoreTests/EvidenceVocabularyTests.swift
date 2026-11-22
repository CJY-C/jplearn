import XCTest
@testable import LearningCore

final class EvidenceVocabularyTests: XCTestCase {
    func testReadingAnswersRespectSenseRestrictionsAndCurrentUsage() throws {
        let pack = try ContentPack.bundled()
        for (id, accepted, rejected) in [("vn3q002", "かくう", "がくう"),
                                         ("vn3q003", "うむ", "ゆうむ"),
                                         ("vn2d066", "しろうと", "しろと")] {
            let word = try XCTUnwrap(pack.item(id))
            XCTAssertTrue(AnswerChecker.matches(accepted, reading: word.reading, alternatives: word.acceptedReadings ?? []))
            XCTAssertFalse(AnswerChecker.matches(rejected, reading: word.reading, alternatives: word.acceptedReadings ?? []))
        }
        let apt = try XCTUnwrap(pack.item("vn2d020"))
        XCTAssertTrue(AnswerChecker.matches("てっかく", reading: apt.reading, alternatives: apt.acceptedReadings ?? []))
    }

    func testSameSoundCannotPrepareANewSpellingOrAnotherMeaning() throws {
        let pack = try ContentPack.bundled(), now = Date(timeIntervalSince1970: 1_790_000_000)
        let old = try XCTUnwrap(pack.items.first { $0.text == "特徴" && $0.lexemeID == nil })
        let device = UUID()
        let events = [old.id, "vn4106"].flatMap { id in [Skill.meaning, .reading].map {
            LearningEvent(deviceID: device, timestamp: now, kind: .review, targetID: id, skill: $0, rating: 3)
        } }
        let knowledge = ReadingKnowledge(pack: pack, events: events, now: now)
        for id in ["vn2d071", "vn2d094"] { // 特長 and 映す
            XCTAssertNil(pack.item(id)?.readingOwnerID)
            XCTAssertFalse(knowledge.recalled(id, .meaning))
            XCTAssertFalse(knowledge.recalled(id, .reading))
        }
    }
}
