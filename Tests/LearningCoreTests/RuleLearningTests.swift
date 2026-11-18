import XCTest
@testable import LearningCore

final class RuleLearningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let device = UUID()

    private func attempt(_ set: RulePracticeSet, at time: Date, correct: Bool = true,
                         assisted: Bool = false) -> [LearningEvent] {
        let context = UUID().uuidString
        return set.questions.map { question in
            LearningEvent(deviceID: device, timestamp: time, kind: .questionAttempt, targetID: question.id,
                assisted: assisted, value: String(correct ? question.answerIndex : (question.answerIndex + 1) % question.choices.count),
                contextID: context, correct: correct && !assisted)
        } + [LearningEvent(deviceID: device, timestamp: time, kind: .placement, targetID: set.id,
            assisted: assisted, value: correct && !assisted ? "passed" : "review", contextID: context)]
    }
    private func rule(_ id: String, _ pack: ContentPack) -> LearningRule { pack.learningRules!.first { $0.id == id }! }
    private func verified(_ rule: LearningRule) -> [LearningEvent] {
        attempt(rule.practiceSets[0], at: now.addingTimeInterval(-86_401)) + attempt(rule.practiceSets[1], at: now)
    }

    func testRulesPreserveRealVocabularyAndExceptionPractice() throws {
        let pack = try ContentPack.bundled()
        XCTAssertEqual(pack.learningRules?.count, 5)
        XCTAssertEqual(pack.wordCount, 3647)
        XCTAssertEqual(pack.learningRules?.flatMap { $0.practiceSets.flatMap(\.questions) }.count, 60)
        let regular = Set(pack.learningRules!.flatMap(\.regularItemIDs))
        XCTAssertEqual(regular, Set(["v0158", "v0160", "vn5007", "v0161", "vn5013"]))
        for id in ["vn5527", "vn5530", "vn5537", "vn5006", "vn6503", "v0159", "vn5726", "vn5172"] {
            XCTAssertFalse(regular.contains(id), "Exceptions, durations and lexicalized words stay independent")
        }
    }

    func testDifferentSetsAndAFullDayAreBothRequired() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let first = attempt(rule.practiceSets[0], at: now.addingTimeInterval(-86_400))
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: first, now: now).verified)
        let same = first + attempt(rule.practiceSets[0], at: now)
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: same, now: now).verified)
        let early = first + attempt(rule.practiceSets[1], at: now.addingTimeInterval(-1))
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: early, now: now).verified)
        XCTAssertTrue(RuleProgress.make(rule, pack: pack, events: verified(rule), now: now).verified)
    }

    func testFlagsIncompleteAnswersAndAssistanceCannotInventTransfer() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let good = verified(rule)
        let flags = good.filter { $0.kind == .placement }
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: flags, now: now).verified)
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: Array(good.dropFirst()), now: now).verified)
        let assisted = attempt(rule.practiceSets[0], at: now.addingTimeInterval(-86_400), assisted: true) +
            attempt(rule.practiceSets[1], at: now)
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: assisted, now: now).verified)
        let conflicting = good + [LearningEvent(deviceID: device, timestamp: now, kind: .questionAttempt,
            targetID: rule.practiceSets[1].questions[0].id, value: "0", contextID: good.last!.contextID, correct: true)]
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: conflicting, now: now).verified)
    }

    func testFailedRoundResetsTransferAndDoesNotRepeatImmediately() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let failureTime = now.addingTimeInterval(60)
        let events = verified(rule) + attempt(rule.practiceSets[2], at: failureTime, correct: false)
        let state = RuleProgress.make(rule, pack: pack, events: events, now: failureTime)
        XCTAssertFalse(state.verified)
        XCTAssertTrue(state.consolidatedKeys.isEmpty)
        XCTAssertEqual(state.successfulSets, 0)
        XCTAssertEqual(state.nextDue, failureTime.addingTimeInterval(86_400))
        let retry = events + attempt(rule.practiceSets[0], at: failureTime.addingTimeInterval(86_401))
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: retry, now: failureTime.addingTimeInterval(86_401)).verified)
    }

    func testSameDayCrammingCannotPostponeTheFirstSpacedCheck() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let history = (0..<9).flatMap { index in
            attempt(rule.practiceSets[index % 3], at: now.addingTimeInterval(Double(index)))
        }
        let state = RuleProgress.make(rule, pack: pack, events: history, now: now.addingTimeInterval(10))
        XCTAssertFalse(state.verified)
        XCTAssertEqual(state.nextDue, now.addingTimeInterval(8 + 86_400))
    }

    func testOneQuestionContextCannotCountAsTwoSpacedSessions() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let first = attempt(rule.practiceSets[0], at: now.addingTimeInterval(-86_400))
        let context = first.last!.contextID
        let second = attempt(rule.practiceSets[1], at: now).map { event in
            LearningEvent(deviceID: event.deviceID, timestamp: event.timestamp, kind: event.kind,
                targetID: event.targetID, value: event.value, contextID: context, correct: event.correct)
        }
        let state = RuleProgress.make(rule, pack: pack, events: first + second, now: now)
        XCTAssertFalse(state.verified)
        XCTAssertEqual(state.successfulSets, 1)
    }

    func testAWordFailureRestoresOnlyTheFailedSkill() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let failed = LearningEvent(deviceID: device, timestamp: now.addingTimeInterval(1), kind: .review,
            targetID: "v0161", skill: .reading, rating: 1)
        let state = RuleProgress.make(rule, pack: pack, events: verified(rule) + [failed], now: failed.timestamp)
        XCTAssertFalse(state.consolidatedKeys.contains(ReviewKey(itemID: "v0161", skill: .reading)))
        XCTAssertTrue(state.consolidatedKeys.contains(ReviewKey(itemID: "v0161", skill: .meaning)))
        XCTAssertTrue(state.consolidatedKeys.contains(ReviewKey(itemID: "vn5013", skill: .reading)))
    }

    func testConsolidationSkipsBothNewAndDueRegularCardsButKeepsExceptions() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let oldTime = now.addingTimeInterval(-30 * 86_400)
        let existing = ["v0161", "vn5006"].map { LearningEvent(deviceID: device, timestamp: oldTime,
            kind: .review, targetID: $0, skill: .reading, rating: 1) }
        let history = existing + verified(rule)
        let due = try ReviewScheduler().dueKeys(events: history, pack: pack, now: now)
        XCTAssertFalse(due.contains(ReviewKey(itemID: "v0161", skill: .reading)))
        XCTAssertTrue(due.contains(ReviewKey(itemID: "vn5006", skill: .reading)))
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 20, now: now)
        XCTAssertFalse(tasks.contains { if case .recall(let key) = $0 { return rule.regularItemIDs.contains(key.itemID) }; return false })
    }

    func testInferredReadingCoverageDoesNotInflateDirectMasteryStatistics() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let history = verified(rule)
        let original = pack.readings[0]
        let passage = ReadingPassage(id: "ruletest", title: "规则迁移", genre: "对话", level: "N5",
            sentenceIDs: original.sentenceIDs, question: original.question, choices: original.choices,
            answerIndex: original.answerIndex, explanation: original.explanation,
            vocabulary: [ReadingWord(text: "二冊", itemID: "v0161"), ReadingWord(text: "一冊", itemID: "vn5006")], grammarIDs: [])
        let state = RuleKnowledge(pack: pack, events: history, now: now)
        let ready = ReadingReadiness.assess(passage, pack: pack,
            knowledge: ReadingKnowledge(events: history, inferredKeys: state.consolidatedKeys))
        XCTAssertEqual(ready.knownOccurrences, 0)
        XCTAssertEqual(ready.inferredOccurrences, 1)
        XCTAssertEqual(ready.percentage, 50)
        XCTAssertEqual(ready.unfamiliarWords.map(\.text), ["一冊"])
        let stats = try LearningStatistics.make(pack: pack, events: history, now: now)
        XCTAssertEqual(stats.reviewCount, 0)
        XCTAssertEqual(stats.levels[0].meaning.remembered, 0)
        XCTAssertEqual(stats.levels[0].reading.remembered, 0)
    }

    func testRulePracticeDoesNotPretendToUpdateAWordForgettingCurve() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let words = ["v0161", "vn5006"].map { LearningEvent(deviceID: device, timestamp: now.addingTimeInterval(-10 * 86_400),
            kind: .review, targetID: $0, skill: .reading, rating: 3) }
        let stats = try LearningStatistics.make(pack: pack, events: words + verified(rule), now: now)
        XCTAssertEqual(stats.forecasts.first { $0.skill == .reading }?.cardCount, 1,
            "Only the independent exceptional word retains a word-level forecast")
        XCTAssertEqual(stats.levels.reduce(0) { $0 + $1.reading.practiced }, 2, "Existing word history across levels is preserved")
    }

    func testRuleQuestionsCountAsPracticeAndActiveDaysWithoutInventingRecall() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulenum", pack)
        let history = attempt(rule.practiceSets[0], at: now)
        let snapshot = LearningSnapshot(events: history)
        XCTAssertEqual(snapshot.practicedToday(at: now), 4)
        XCTAssertEqual(snapshot.reviewedToday(at: now), 0)
        let stats = try LearningStatistics.make(pack: pack, events: history, now: now)
        XCTAssertEqual(stats.activeDays, 1)
        XCTAssertEqual(stats.days.last?.reviews, 4)
        XCTAssertEqual(stats.reviewCount, 0)
        XCTAssertNil(stats.recallRate)
    }

    func testDailyPlanningRotatesSetsAndRespectsCooldownWithoutNewWordInflation() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulenum", pack)
        let first = try SessionPlanner.make(pack: pack, events: [], minutes: 20, now: now)
        XCTAssertEqual(first.filter { if case .rule = $0 { return true }; return false }.map(\.id), ["rule:" + rule.practiceSets[0].id])
        // Empty word prerequisite lists in this rule do not unlock all dependent rules.
        let knowledge = RuleKnowledge(pack: pack, events: [], now: now)
        XCTAssertFalse(knowledge.ready(self.rule("rulemonth", pack)))
        let history = attempt(rule.practiceSets[0], at: now)
        let state = RuleProgress.make(rule, pack: pack, events: history, now: now)
        XCTAssertEqual(state.nextSetID, rule.practiceSets[1].id)
        XCTAssertGreaterThan(state.nextDue!, now)
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 20, now: now, newWordLimit: 1)
        XCTAssertFalse(tasks.contains { $0.id == "rule:" + rule.practiceSets[1].id })
        let wordIDs = tasks.compactMap { if case .recall(let key) = $0 { return key.itemID }; return nil }
        XCTAssertEqual(Set(wordIDs).count, 1)
        XCTAssertTrue(RuleKnowledge(pack: pack, events: history, now: now).ready(self.rule("rulemonth", pack)))
    }

    func testHistoryOrderMergeAndFutureRecordsDoNotChangeEvidence() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulebooks", pack)
        let events = verified(rule)
        let merged = try EventMerge.merge(events, Array(events.reversed()))
        XCTAssertEqual(merged.count, events.count)
        XCTAssertTrue(RuleProgress.make(rule, pack: pack, events: merged, now: now).verified)
        XCTAssertTrue(RuleProgress.make(rule, pack: pack, events: Array(events.reversed()), now: now).verified)
        XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: merged, now: now.addingTimeInterval(-1)).verified)
    }

    func testLegacyPackAndCheckpointsRemainReadable() throws {
        let pack = try ContentPack.bundled()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any])
        object.removeValue(forKey: "learningRules")
        let old = try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: object))
        try old.validate()
        XCTAssertNil(old.learningRules)
        let checkpoint = SessionCheckpoint(tasks: [.recall(ReviewKey(itemID: "v0001", skill: .reading)), .reading("r001")])
        let restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self, from: ExchangeCoding.encoder().encode(checkpoint))
        try restored.validate()
        XCTAssertEqual(restored.entries.map { $0.task.id }, checkpoint.entries.map { $0.task.id })
    }
}
