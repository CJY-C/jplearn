import XCTest
@testable import LearningCore

final class BasisChapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let device = UUID()

    private func review(_ id: String, _ skill: Skill) -> LearningEvent {
        LearningEvent(deviceID: device, timestamp: now, kind: .review, targetID: id, skill: skill, rating: 3)
    }

    func testBoardingPlaceIsOneEarlierWordAndTheOldContextUsesItsMeaning() throws {
        let pack = try ContentPack.bundled(), word = try XCTUnwrap(pack.item("vn5b001"))
        XCTAssertEqual(word.level, "N5")
        XCTAssertEqual(word.reading, "のりば")
        XCTAssertNil(word.lexemeID)
        XCTAssertEqual(word.exampleSentenceIDs?.count, 2)
        XCTAssertEqual(pack.items.filter { $0.text == "乗り場" && $0.isLexeme }.count, 1)
        let old = try XCTUnwrap(pack.sentence("svn5956a"))
        XCTAssertEqual(old.text, "駅員に乗り場を聞きました。")
        XCTAssertEqual(old.segments.filter { $0.text == "乗り場" }.compactMap(\.itemID), [word.id])
    }

    func testNewExpressionNeedsIndependentRecallEvenWithCompleteWordCoverage() throws {
        let pack = try ContentPack.bundled(), reading = try XCTUnwrap(pack.readings.first { $0.id == "rn2104" })
        let wordIDs = Set((reading.vocabulary ?? []).compactMap(\.itemID))
        var events = wordIDs.map { review($0, .meaning) }
        events += (reading.grammarIDs ?? []).filter { $0 != "gn2b006" }.map { review($0, .grammar) }
        func readiness() -> ReadingReadiness {
            ReadingReadiness.assess(reading, pack: pack,
                knowledge: ReadingKnowledge(pack: pack, events: events, now: now))
        }
        XCTAssertEqual(readiness().percentage, 100)
        XCTAssertEqual(readiness().missingGrammarIDs, ["gn2b006"])
        XCTAssertFalse(readiness().isEligible)
        events.append(review("gn2b006", .grammar))
        XCTAssertTrue(readiness().isEligible)
    }

    func testBoardingPlaceReadingCannotPretendItsMeaningIsKnownInThePassage() throws {
        let pack = try ContentPack.bundled(), reading = try XCTUnwrap(pack.readings.first { $0.id == "rn2108" })
        let words = reading.vocabulary ?? []
        let occurrences = words.filter { $0.itemID == "vn5b001" }.count
        XCTAssertEqual(occurrences, 3)
        var events = Set(words.compactMap(\.itemID)).filter { $0 != "vn5b001" }.map { review($0, .meaning) }
        events += (reading.grammarIDs ?? []).map { review($0, .grammar) }
        events.append(review("vn5b001", .reading))
        func readiness() -> ReadingReadiness {
            ReadingReadiness.assess(reading, pack: pack,
                knowledge: ReadingKnowledge(pack: pack, events: events, now: now))
        }
        XCTAssertEqual(readiness().knownOccurrences, words.count - occurrences)
        XCTAssertEqual(readiness().unfamiliarWords.compactMap(\.itemID), ["vn5b001"])
        XCTAssertEqual(readiness().inferredOccurrences, 0)
        events.append(review("vn5b001", .meaning))
        XCTAssertEqual(readiness().percentage, 100)
        XCTAssertTrue(readiness().isEligible)
    }
}
