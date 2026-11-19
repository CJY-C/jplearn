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
        XCTAssertEqual(pack.learningRules?.count, 7)
        XCTAssertEqual(pack.wordCount, 3868)
        XCTAssertEqual(pack.learningRules?.flatMap { $0.practiceSets.flatMap(\.questions) }.count, 84)
        let regular = Set(pack.learningRules!.flatMap(\.regularItemIDs))
        XCTAssertEqual(regular, Set(["v0158", "v0160", "vn5007", "v0161", "vn5013"]))
        for id in ["vn5527", "vn5530", "vn5537", "vn5006", "vn6503", "v0159", "vn5726", "vn5172"] {
            XCTAssertFalse(regular.contains(id), "Exceptions, durations and lexicalized words stay independent")
        }
    }

    func testRuleStudyChoiceRestoresBeforeAnswerAndCannotEraseAssistance() throws {
        var checkpoint = SessionCheckpoint(tasks: [.rule("rulemonths1")])
        let id = try XCTUnwrap(checkpoint.current?.id)
        XCTAssertNil(checkpoint.ruleStudyMode(for: id))
        try checkpoint.selectRuleStudyMode(.learn, entryID: id)
        let restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self,
            from: ExchangeCoding.encoder().encode(checkpoint))
        try restored.validate()
        XCTAssertEqual(restored.ruleStudyMode(for: id), .learn)
        XCTAssertTrue(restored.assistedEntryIDs.contains(id))
        var practice = restored
        try practice.selectRuleStudyMode(.verify, entryID: id)
        let reopened = try ExchangeCoding.decoder().decode(SessionCheckpoint.self,
            from: ExchangeCoding.encoder().encode(practice))
        try reopened.validate()
        XCTAssertEqual(reopened.ruleStudyMode(for: id), .verify)
        XCTAssertTrue(reopened.assistedEntryIDs.contains(id), "Starting questions cannot undo seeing the explanation")
        XCTAssertNil(reopened.questionIndex, "The choice itself does not answer or advance a question")
    }

    func testLegacyCheckpointHasNoImplicitRuleStudyChoice() throws {
        let checkpoint = SessionCheckpoint(tasks: [.rule("rulemonths1")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ExchangeCoding.encoder().encode(checkpoint)) as? [String: Any])
        object.removeValue(forKey: "ruleStudyModes")
        let restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self,
            from: JSONSerialization.data(withJSONObject: object))
        try restored.validate()
        XCTAssertNil(restored.ruleStudyMode(for: try XCTUnwrap(restored.current?.id)))
        XCTAssertTrue(restored.assistedEntryIDs.isEmpty)
    }

    func testRuleStudyChoiceRejectsStaleEntriesAndOtherTasks() throws {
        var checkpoint = SessionCheckpoint(tasks: [.rule("rulemonths1"), .reading("r001")])
        let ruleID = try XCTUnwrap(checkpoint.current?.id), readingID = checkpoint.entries[1].id
        XCTAssertThrowsError(try checkpoint.selectRuleStudyMode(.verify, entryID: readingID))
        try checkpoint.selectRuleStudyMode(.verify, entryID: ruleID)
        checkpoint.index = 1
        XCTAssertThrowsError(try checkpoint.selectRuleStudyMode(.learn, entryID: ruleID))
        XCTAssertThrowsError(try checkpoint.selectRuleStudyMode(.learn, entryID: readingID))
        XCTAssertTrue(checkpoint.assistedEntryIDs.isEmpty)
        try checkpoint.validate()
    }

    func testMalformedRuleStudyModesCannotRestoreAsUnassistedEvidence() throws {
        let checkpoint = SessionCheckpoint(tasks: [.rule("rulemonths1"), .reading("r001")])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: ExchangeCoding.encoder().encode(checkpoint)) as? [String: Any])
        for modes in [[checkpoint.entries[0].id.uuidString: "learn"],
                      [checkpoint.entries[1].id.uuidString: "verify"],
                      [UUID().uuidString: "verify"]] {
            var invalid = object
            invalid["ruleStudyModes"] = modes
            let restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self,
                from: JSONSerialization.data(withJSONObject: invalid))
            XCTAssertThrowsError(try restored.validate())
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

    func testProductiveFormsRequireTheirOwnVocabularyInsteadOfNumberKnowledge() throws {
        let pack = try ContentPack.bundled(), verb = rule("ruleverbforms", pack)
        let numbers = verified(rule("rulenum", pack))
        XCTAssertFalse(RuleKnowledge(pack: pack, events: numbers, now: now).ready(verb))
        let onlyMeanings = verb.prerequisiteIDs.map { LearningEvent(deviceID: device, timestamp: now,
            kind: .review, targetID: $0, skill: .meaning, rating: 3) }
        XCTAssertFalse(RuleKnowledge(pack: pack, events: numbers + onlyMeanings, now: now).ready(verb))
        let readings = verb.prerequisiteIDs.map { LearningEvent(deviceID: device, timestamp: now,
            kind: .review, targetID: $0, skill: .reading, rating: 3) }
        XCTAssertTrue(RuleKnowledge(pack: pack, events: onlyMeanings + readings, now: now).ready(verb))
        XCTAssertFalse(RuleKnowledge(pack: pack, events: onlyMeanings + readings, now: now)
            .ready(rule("ruleadjectiveforms", pack)))
    }

    func testGuidedCorrectRoundAllowsDependentLearningWithoutInventingTransfer() throws {
        let pack = try ContentPack.bundled(), numbers = rule("rulenum", pack)
        let history = attempt(numbers.practiceSets[0], at: now, assisted: true)
        let knowledge = RuleKnowledge(pack: pack, events: history, now: now)
        let progress = try XCTUnwrap(knowledge.progress[numbers.id])
        XCTAssertTrue(progress.hasLearnedFoundation)
        XCTAssertEqual(progress.title, "已学规则，待独立验证")
        XCTAssertEqual(progress.successfulSets, 0)
        XCTAssertFalse(progress.verified)
        XCTAssertTrue(progress.confirmedQuestionIDs.isEmpty)
        XCTAssertTrue(knowledge.consolidatedKeys.isEmpty)
        XCTAssertTrue(knowledge.ready(rule("rulemonth", pack)), "Beginners can learn months after guided number practice")
        XCTAssertFalse(knowledge.ready(rule("ruleverbforms", pack)))
        let tasks = try SessionPlanner.make(pack: pack, events: history, minutes: 10, now: now,
            newWordLimit: 0, newGrammarLimit: 0)
        XCTAssertEqual(tasks.filter { if case .rule = $0 { return true }; return false }.map(\.id),
            ["rule:" + rule("rulemonth", pack).practiceSets[0].id],
            "Continue with dependent learning instead of immediately repeating numbers or waiting a day")
        let direct = ReadingKnowledge(pack: pack, events: history, now: now)
        for id in rule("rulemonth", pack).prerequisiteIDs {
            XCTAssertFalse(direct.recalled(id, .reading))
            XCTAssertFalse(direct.recalled(id, .meaning))
        }
    }

    func testFailedIncompleteOrContradictoryGuidedRoundsCannotUnlockDependents() throws {
        let pack = try ContentPack.bundled(), numbers = rule("rulenum", pack)
        let good = attempt(numbers.practiceSets[0], at: now, assisted: true)
        let failed = attempt(numbers.practiceSets[1], at: now.addingTimeInterval(1), correct: false, assisted: true)
        let inconsistent = attempt(numbers.practiceSets[0], at: now).map { event in
            LearningEvent(deviceID: event.deviceID, timestamp: event.timestamp, kind: event.kind,
                targetID: event.targetID, assisted: false, value: event.value, contextID: event.contextID, correct: false)
        }
        for history in [Array(good.dropFirst()), good.filter { $0.kind == .placement }, inconsistent, good + failed] {
            let knowledge = RuleKnowledge(pack: pack, events: history, now: now.addingTimeInterval(2))
            XCTAssertFalse(knowledge.progress[numbers.id]?.hasLearnedFoundation ?? true)
            XCTAssertFalse(knowledge.ready(rule("rulemonth", pack)))
        }
    }

    func testFormTransferCannotConsolidateLemmaMeaningReadingOrOtherGrammar() throws {
        let pack = try ContentPack.bundled()
        for id in ["ruleverbforms", "ruleadjectiveforms"] {
            let formRule = rule(id, pack)
            let history = verified(formRule)
            let knowledge = RuleKnowledge(pack: pack, events: history, now: now)
            XCTAssertTrue(knowledge.progress[id]!.verified)
            XCTAssertTrue(knowledge.consolidatedKeys.isEmpty)
            for lemma in formRule.prerequisiteIDs {
                let direct = ReadingKnowledge(pack: pack, events: history, now: now)
                XCTAssertFalse(direct.recalled(lemma, .reading))
                XCTAssertFalse(direct.recalled(lemma, .meaning))
            }
            let stats = try LearningStatistics.make(pack: pack, events: history, now: now)
            XCTAssertEqual(stats.reviewCount, 0)
            XCTAssertEqual(stats.levels.reduce(0) { $0 + $1.meaning.remembered + $1.reading.remembered }, 0)
        }
    }

    func testLemmaReviewsRemainDueAfterFormTransfer() throws {
        let pack = try ContentPack.bundled(), verb = rule("ruleverbforms", pack)
        let old = verb.prerequisiteIDs.flatMap { id in [Skill.reading, .meaning].map {
            LearningEvent(deviceID: device, timestamp: now.addingTimeInterval(-30 * 86_400),
                kind: .review, targetID: id, skill: $0, rating: 1)
        } }
        let due = try ReviewScheduler().dueKeys(events: old + verified(verb), pack: pack, now: now)
        for id in verb.prerequisiteIDs {
            XCTAssertTrue(due.contains(ReviewKey(itemID: id, skill: .meaning)))
            XCTAssertTrue(due.contains(ReviewKey(itemID: id, skill: .reading)))
        }
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

    private func calendarPassage(_ pack: ContentPack) -> ReadingPassage {
        let original = pack.readings[0]
        return ReadingPassage(id: "calendartest", title: "日期", genre: "通知", level: "N5",
            sentenceIDs: original.sentenceIDs, question: original.question, choices: original.choices,
            answerIndex: original.answerIndex, explanation: original.explanation,
            vocabulary: [ReadingWord(text: "四", itemID: "vn5504")], grammarIDs: [],
            rulePrerequisites: [ReadingRulePrerequisite(ruleID: "rulemonth", questionIDs: ["rulemonths1q3"])])
    }

    func testReadingNeedsBothRuleTransferAndItsSpecificException() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulemonth", pack)
        let passage = calendarPassage(pack)
        let word = LearningEvent(deviceID: device, timestamp: now, kind: .review,
            targetID: "vn5504", skill: .meaning, rating: 3)
        var history = [word]
        func readiness() -> ReadingReadiness {
            ReadingReadiness.assess(passage, pack: pack, knowledge: ReadingKnowledge(pack: pack, events: history, now: now))
        }
        XCTAssertEqual(readiness().percentage, 100)
        XCTAssertEqual(readiness().missingRuleIDs, [rule.id])
        XCTAssertFalse(readiness().isEligible)
        history += attempt(rule.practiceSets[1], at: now.addingTimeInterval(-86_400))
        history += attempt(rule.practiceSets[2], at: now)
        XCTAssertTrue(RuleProgress.make(rule, pack: pack, events: history, now: now).verified)
        XCTAssertFalse(readiness().isEligible, "General month transfer does not prove April's irregular reading")
        history += attempt(rule.practiceSets[0], at: now)
        XCTAssertTrue(readiness().isEligible)
        XCTAssertTrue(readiness().missingRuleIDs.isEmpty)
        XCTAssertTrue(SessionPlanner.readingAvailable(passage, pack: pack, events: history, now: now))
    }

    func testExceptionNeedsAnUnassistedCompleteRoundAndResetsOnFailure() throws {
        let pack = try ContentPack.bundled(), rule = rule("rulemonth", pack)
        let general = attempt(rule.practiceSets[1], at: now.addingTimeInterval(-86_400)) + attempt(rule.practiceSets[2], at: now)
        let question = "rulemonths1q3"
        for invalid in [attempt(rule.practiceSets[0], at: now, assisted: true),
                        Array(attempt(rule.practiceSets[0], at: now).dropFirst()),
                        attempt(rule.practiceSets[0], at: now).filter { $0.kind == .placement }] {
            XCTAssertFalse(RuleProgress.make(rule, pack: pack, events: general + invalid, now: now).confirmedQuestionIDs.contains(question))
        }
        let good = general + attempt(rule.practiceSets[0], at: now)
        XCTAssertTrue(RuleProgress.make(rule, pack: pack, events: good, now: now).confirmedQuestionIDs.contains(question))
        let failedAt = now.addingTimeInterval(1)
        let failed = good + attempt(rule.practiceSets[1], at: failedAt, correct: false)
        let state = RuleProgress.make(rule, pack: pack, events: failed, now: failedAt)
        XCTAssertFalse(state.verified)
        XCTAssertTrue(state.confirmedQuestionIDs.isEmpty)
    }

    func testReadingCannotReferenceAnotherRulesExceptionOrUnknownRule() throws {
        let pack = try ContentPack.bundled()
        var passage = calendarPassage(pack)
        for prerequisite in [ReadingRulePrerequisite(ruleID: "rulemonth", questionIDs: ["rulebooks1q1"]),
                             ReadingRulePrerequisite(ruleID: "missingrule", questionIDs: [])] {
            passage.rulePrerequisites = [prerequisite]
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any])
            var readings = try XCTUnwrap(object["readings"] as? [[String: Any]])
            readings.append(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(passage)) as? [String: Any]))
            object["readings"] = readings
            let invalid = try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try invalid.validate())
        }
    }

    func testLegacyPackAndCheckpointsRemainReadable() throws {
        let pack = try ContentPack.bundled()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any])
        object.removeValue(forKey: "learningRules")
        let dangling = try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try dangling.validate(), "Removing referenced rules does not create a valid legacy pack")
        var readings = try XCTUnwrap(object["readings"] as? [[String: Any]])
        for index in readings.indices { readings[index].removeValue(forKey: "rulePrerequisites") }
        object["readings"] = readings
        let old = try JSONDecoder().decode(ContentPack.self, from: JSONSerialization.data(withJSONObject: object))
        try old.validate()
        XCTAssertNil(old.learningRules)
        XCTAssertTrue(old.readings.allSatisfy { $0.rulePrerequisites == nil })
        let checkpoint = SessionCheckpoint(tasks: [.recall(ReviewKey(itemID: "v0001", skill: .reading)), .reading("r001")])
        let restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self, from: ExchangeCoding.encoder().encode(checkpoint))
        try restored.validate()
        XCTAssertEqual(restored.entries.map { $0.task.id }, checkpoint.entries.map { $0.task.id })
    }
}
