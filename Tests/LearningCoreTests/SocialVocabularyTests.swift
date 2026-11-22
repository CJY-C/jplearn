import XCTest
@testable import LearningCore

final class SocialVocabularyTests: XCTestCase {
    func testCurrentAlternativeReadingsAreAcceptedWithinTheirSelectedSenses() throws {
        let pack = try ContentPack.bundled()
        for (id, accepted) in [("vn2e011", "わたくしりつ"), ("vn2e012", "しょたい"),
                               ("vn2e014", "せろん"), ("vn2e014", "せいろん"),
                               ("vn2e026", "かいじょう"), ("vn2e027", "せこう"),
                               ("vn2e078", "ちんきん"), ("vn3r009", "しょうがっきん")] {
            let word = try XCTUnwrap(pack.item(id))
            XCTAssertTrue(AnswerChecker.matches(accepted, reading: word.reading, alternatives: word.acceptedReadings ?? []), id)
        }
        let law = try XCTUnwrap(pack.item("vn2e027"))
        for otherSense in ["しぎょう", "せぎょう"] {
            XCTAssertFalse(AnswerChecker.matches(otherSense, reading: law.reading, alternatives: law.acceptedReadings ?? []))
        }
        let relief = try XCTUnwrap(pack.item("vn2e105"))
        for otherSense in ["くさい", "ぐさい"] {
            XCTAssertFalse(AnswerChecker.matches(otherSense, reading: relief.reading, alternatives: relief.acceptedReadings ?? []))
        }
    }

    func testFundraisingKnowledgeCannotProveTheDonatingMeaning() throws {
        let pack = try ContentPack.bundled()
        let root = try XCTUnwrap(pack.item("vn2e106")), donation = try XCTUnwrap(pack.item("vn2e112"))
        XCTAssertEqual(donation.readingOwnerID, root.id)
        XCTAssertEqual(donation.skills, [.meaning])
        let passage = ReadingPassage(id: "donor-sense", title: "募金", genre: "用法", level: "N2",
            sentenceIDs: donation.exampleSentenceIDs ?? [], question: "词义", choices: ["甲", "乙"], answerIndex: 0,
            explanation: "用法检查", vocabulary: [ReadingWord(text: donation.text, itemID: donation.id)], grammarIDs: [])
        let history = [Skill.meaning, .reading].map {
            LearningEvent(deviceID: UUID(), kind: .review, targetID: root.id, skill: $0, rating: 3)
        }
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history).knownOccurrences, 0)
        let own = LearningEvent(deviceID: UUID(), kind: .review, targetID: donation.id, skill: .meaning, rating: 3)
        XCTAssertEqual(ReadingReadiness.assess(passage, pack: pack, events: history + [own]).knownOccurrences, 1)
    }

    func testNewDonationMeaningDoesNotScheduleASecondReadingCard() throws {
        let pack = try ContentPack.bundled(), now = Date()
        let history = pack.items.filter { $0.id != "vn2e112" }.flatMap { item in item.skills.map {
            LearningEvent(deviceID: UUID(), timestamp: now.addingTimeInterval(-86_400), kind: .review,
                targetID: item.id, skill: $0, rating: 4)
        } }
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 5, now: now,
                                           newWordLimit: 5, newGrammarLimit: 0)
        let keys = tasks.compactMap { task -> ReviewKey? in
            if case .recall(let key) = task { return key }; return nil
        }
        XCTAssertTrue(keys.contains(ReviewKey(itemID: "vn2e112", skill: .meaning)))
        XCTAssertFalse(keys.contains(ReviewKey(itemID: "vn2e112", skill: .reading)))
    }
}
