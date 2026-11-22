import XCTest
@testable import LearningCore

final class WordReadingGuideTests: XCTestCase {
    func testOkuriganaAnchorsConnectReadingToTheCorrectKanjiClusters() {
        let segments = WordReadingGuide.segments(text: "食べ物", reading: "たべもの", itemID: "food")
        XCTAssertEqual(segments.map(\.text), ["食", "べ", "物"])
        XCTAssertEqual(segments.map(\.reading), ["た", nil, "もの"])
        XCTAssertTrue(segments.allSatisfy { $0.itemID == "food" })
        let verb = WordReadingGuide.segments(text: "取り戻す", reading: "とりもどす")
        XCTAssertEqual(verb.map(\.reading), ["と", nil, "もど", nil])
    }

    func testJukujikunAndKanjiClustersAreNotGivenInventedCharacterReadings() {
        for (word, reading) in [("今日", "きょう"), ("大人", "おとな"), ("手紙", "てがみ")] {
            let segments = WordReadingGuide.segments(text: word, reading: reading)
            XCTAssertEqual(segments.count, 1)
            XCTAssertEqual(segments.first?.text, word)
            XCTAssertEqual(segments.first?.reading, reading)
        }
    }

    func testKanaAndLongVowelsRemainLiteralWhileKatakanaCanAnchor() {
        let kana = WordReadingGuide.segments(text: "コーヒー", reading: "こーひー")
        XCTAssertEqual(kana.first?.text, "コーヒー")
        XCTAssertNil(kana.first?.reading)
        let mixed = WordReadingGuide.segments(text: "消しゴム", reading: "けしごむ")
        XCTAssertEqual(mixed.map(\.text), ["消", "しゴム"])
        XCTAssertEqual(mixed.map(\.reading), ["け", nil])
    }

    func testAmbiguousOrUnmatchedAlignmentFallsBackToWholeWord() {
        let ambiguous = WordReadingGuide.segments(text: "甲あ乙", reading: "かああき")
        XCTAssertEqual(ambiguous.count, 1)
        XCTAssertEqual(ambiguous.first?.reading, "かああき")
        let unmatched = WordReadingGuide.segments(text: "行く", reading: "ゆき")
        XCTAssertEqual(unmatched.count, 1)
        XCTAssertEqual(unmatched.first?.reading, "ゆき")
        XCTAssertTrue(WordReadingGuide.segments(text: "", reading: "").isEmpty)
    }
}
