import XCTest
@testable import LearningCore

final class PitchAccentTests: XCTestCase {
    func testFlatAndFinalAccentsRemainDifferentWhenAParticleFollows() throws {
        let pack = try ContentPack.bundled()
        let nose = try XCTUnwrap(pack.item("vn5106")?.pitchAccents?.first)
        let flower = try XCTUnwrap(pack.item("v0221")?.pitchAccents?.first)
        XCTAssertEqual(nose.markedReading + "が", "はなが")
        XCTAssertEqual(flower.markedReading + "が", "はな↓が")
        XCTAssertEqual(nose.patternName, "平板型")
        XCTAssertEqual(flower.patternName, "尾高型")
        XCTAssertEqual(nose.explanation, "没有词汇性下降")
    }
    func testDropAfterMoraIsNotACharacterIndexOrVolumeInstruction() throws {
        let pack = try ContentPack.bundled()
        let rain = try XCTUnwrap(pack.item("v0083")?.pitchAccents?.first)
        let summer = try XCTUnwrap(pack.item("vn5202")?.pitchAccents?.first)
        XCTAssertEqual(rain.markedReading, "あ↓め")
        XCTAssertEqual(rain.patternName, "头高型")
        XCTAssertEqual(summer.markedReading, "なつや↓すみ")
        XCTAssertEqual(summer.patternName, "中高型")
        let contracted = WordPitchAccent(reading: "きょう", morae: ["きょ", "う"], dropAfter: 1,
                                         dialect: "test", citations: rain.citations)
        XCTAssertTrue(contracted.isValid)
        XCTAssertEqual(contracted.markedReading, "きょ↓う")
    }
    func testMissingOrInvalidAccentDataDoesNotBecomeAFlatReference() throws {
        let pack = try ContentPack.bundled()
        XCTAssertNil(pack.item("v0001")?.pitchAccents)
        for changes in [["dropAfter": 9], ["reading": "あま"], ["citations": []]] as [[String: Any]] {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as! [String: Any]
            var items = json["items"] as! [[String: Any]]
            let index = try XCTUnwrap(items.firstIndex { $0["id"] as? String == "v0083" })
            var accents = items[index]["pitchAccents"] as! [[String: Any]]
            accents[0].merge(changes) { _, replacement in replacement }
            items[index]["pitchAccents"] = accents; json["items"] = items
            let invalid = try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try invalid.validate())
        }
    }
    func testNotationDiagnosisDoesNotRequireUnverifiedSyntheticAudio() throws {
        let pack = try ContentPack.bundled()
        let modules = try XCTUnwrap(pack.introModules).filter { ["intro7", "intro8", "intro9"].contains($0.id) }
        XCTAssertEqual(modules.count, 3)
        XCTAssertTrue(modules.allSatisfy { $0.allowsSyntheticSpeech == false && $0.questions.count == 5 })
        XCTAssertTrue(modules.flatMap(\.questions).allSatisfy { $0.ability == "pitchNotation" })
        XCTAssertEqual(pack.item("v0083")?.skills, [.reading, .meaning])
    }
}
