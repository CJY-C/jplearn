import XCTest
import LearningCore
@testable import JPLearn

final class RuleProgressTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @MainActor func testRuleAnswersResumeAfterReopeningAndDoNotInventWordReviews() throws {
        let folder = try directory(), model = try AppModel(storageDirectory: folder)
        let rule = try XCTUnwrap(model.pack.learningRules?.first), set = rule.practiceSets[0]
        try model.startRule(rule)
        let id = try XCTUnwrap(model.checkpoint?.current?.id), first = set.questions[0]
        try model.recordRuleSelection(entryID: id, questionID: first.id, selection: first.answerIndex)
        try model.recordRuleSelection(entryID: id, questionID: first.id, selection: first.answerIndex)
        XCTAssertEqual(model.events.filter { $0.kind == .questionAttempt }.count, 1)
        let restored = try AppModel(storageDirectory: folder)
        try restored.resumeSession()
        XCTAssertEqual(restored.checkpoint?.current?.id, id)
        XCTAssertEqual(restored.checkpoint?.questionIndex, 1)
        for question in set.questions.dropFirst() {
            try restored.recordRuleSelection(entryID: id, questionID: question.id, selection: question.answerIndex)
            try restored.advanceRuleQuestion(entryID: id, questionID: question.id)
        }
        XCTAssertNil(restored.checkpoint?.current)
        XCTAssertEqual(restored.events.filter { $0.kind == .placement }.count, 1)
        XCTAssertEqual(restored.events.first { $0.kind == .placement }?.value, "passed")
        XCTAssertFalse(restored.events.contains { $0.kind == .review })
        let archived = try ArchiveCodec.decode(restored.exportBackup())
        XCTAssertEqual(archived.schemaVersion, 3)
        XCTAssertEqual(archived.events, restored.events)
    }

    @MainActor func testRuleAssistanceSurvivesRestoreAndStaleContinueCannotAdvanceTwice() throws {
        let folder = try directory(), model = try AppModel(storageDirectory: folder)
        let rule = try XCTUnwrap(model.pack.learningRules?.first), set = rule.practiceSets[0]
        try model.startRule(rule)
        let id = try XCTUnwrap(model.checkpoint?.current?.id)
        try model.markAssisted(entryID: id)
        let restored = try AppModel(storageDirectory: folder)
        try restored.resumeSession()
        for question in set.questions {
            try restored.recordRuleSelection(entryID: id, questionID: question.id, selection: question.answerIndex)
            try restored.advanceRuleQuestion(entryID: id, questionID: question.id)
            let index = restored.checkpoint?.questionIndex
            try restored.advanceRuleQuestion(entryID: id, questionID: question.id)
            XCTAssertEqual(restored.checkpoint?.questionIndex, index)
        }
        XCTAssertEqual(restored.events.first { $0.kind == .placement }?.value, "review")
        XCTAssertTrue(restored.events.filter { $0.kind == .questionAttempt }.allSatisfy(\.assisted))
        XCTAssertTrue(RuleProgress.make(rule, pack: restored.pack, events: restored.events).consolidatedKeys.isEmpty)
    }

    @MainActor func testManualDiagnosisStartsBeforePrerequisiteCardsAndRestoresWithoutShowingRules() throws {
        let folder = try directory(), model = try AppModel(storageDirectory: folder)
        let rule = try XCTUnwrap(model.pack.learningRules?.first { $0.id == "rulemonth" })
        XCTAssertFalse(RuleKnowledge(pack: model.pack, events: model.events).ready(rule))
        XCTAssertThrowsError(try model.startRule(rule), "Automatic/default entry still requires the listed foundation")
        try model.startRule(rule, mode: .verify)
        let id = try XCTUnwrap(model.checkpoint?.current?.id)
        let restored = try AppModel(storageDirectory: folder)
        try restored.resumeSession()
        XCTAssertEqual(restored.checkpoint?.ruleStudyMode(for: id), .verify)
        XCTAssertFalse(restored.checkpoint?.assistedEntryIDs.contains(id) ?? true)
        let set = rule.practiceSets[0]
        for question in set.questions {
            try restored.recordRuleSelection(entryID: id, questionID: question.id, selection: question.answerIndex)
            try restored.advanceRuleQuestion(entryID: id, questionID: question.id)
        }
        XCTAssertEqual(restored.events.first { $0.kind == .placement }?.value, "passed")
        XCTAssertFalse(restored.events.contains { $0.kind == .review }, "Diagnosis does not invent prerequisite word mastery")
        let progress = RuleProgress.make(rule, pack: restored.pack, events: restored.events)
        XCTAssertEqual(progress.successfulSets, 1)
        XCTAssertFalse(progress.verified, "One immediate diagnosis is not delayed transfer evidence")
    }

    @MainActor func testLearningExplanationRemainsAssistedAfterSwitchingToQuestionsAndReopening() throws {
        let folder = try directory(), model = try AppModel(storageDirectory: folder)
        let rule = try XCTUnwrap(model.pack.learningRules?.first { $0.id == "rulemonth" })
        try model.startRule(rule, mode: .learn)
        let id = try XCTUnwrap(model.checkpoint?.current?.id)
        let learning = try AppModel(storageDirectory: folder)
        try learning.resumeSession()
        XCTAssertEqual(learning.checkpoint?.ruleStudyMode(for: id), .learn)
        XCTAssertTrue(learning.checkpoint?.assistedEntryIDs.contains(id) ?? false)
        try learning.selectRuleStudyMode(.verify, entryID: id)
        let restored = try AppModel(storageDirectory: folder)
        try restored.resumeSession()
        XCTAssertEqual(restored.checkpoint?.ruleStudyMode(for: id), .verify)
        for question in rule.practiceSets[0].questions {
            try restored.recordRuleSelection(entryID: id, questionID: question.id, selection: question.answerIndex)
            try restored.advanceRuleQuestion(entryID: id, questionID: question.id)
        }
        XCTAssertEqual(restored.events.first { $0.kind == .placement }?.value, "review")
        XCTAssertTrue(restored.events.filter { $0.kind == .questionAttempt }.allSatisfy(\.assisted))
        XCTAssertEqual(RuleProgress.make(rule, pack: restored.pack, events: restored.events).successfulSets, 0)
    }

    @MainActor func testFailedRuleRechecksQueuedCalendarReadingBeforeAdvancing() throws {
        let folder = try directory(), first = try AppModel(storageDirectory: folder), now = Date()
        let rule = try XCTUnwrap(first.pack.learningRules?.first { $0.id == "rulemonth" })
        var history = first.pack.items.flatMap { item in item.skills.map {
            LearningEvent(deviceID: first.deviceID, timestamp: now.addingTimeInterval(-10), kind: .review,
                targetID: item.id, skill: $0, rating: 3)
        } }
        for (index, set) in rule.practiceSets.enumerated() {
            let context = UUID().uuidString
            let time = now.addingTimeInterval(Double(index - 2) * 86_400 - 60)
            history += set.questions.map { LearningEvent(deviceID: first.deviceID, timestamp: time,
                kind: .questionAttempt, targetID: $0.id, value: String($0.answerIndex), contextID: context, correct: true) }
            history.append(LearningEvent(deviceID: first.deviceID, timestamp: time, kind: .placement,
                targetID: set.id, value: "passed", contextID: context))
        }
        try first.append(history)
        let set = rule.practiceSets[0]
        let checkpoint = SessionCheckpoint(tasks: [.rule(set.id), .reading("rn2002"),
            .recall(ReviewKey(itemID: "v0001", skill: .meaning))])
        try ExchangeCoding.encoder().encode(checkpoint).write(to: folder.appendingPathComponent("session.json"))
        let restored = try AppModel(storageDirectory: folder)
        try restored.resumeSession()
        XCTAssertEqual(restored.checkpoint?.entries.count, 3)
        let entryID = try XCTUnwrap(restored.checkpoint?.current?.id)
        for question in set.questions {
            try restored.recordRuleSelection(entryID: entryID, questionID: question.id,
                selection: (question.answerIndex + 1) % question.choices.count)
            try restored.advanceRuleQuestion(entryID: entryID, questionID: question.id)
        }
        guard case .recall(let key)? = restored.checkpoint?.current?.task else {
            return XCTFail("The unavailable reading should be removed while the following study remains")
        }
        XCTAssertEqual(key.itemID, "v0001")
        XCTAssertFalse(restored.events.contains { $0.kind == .readingAttempt })
        XCTAssertFalse(RuleProgress.make(rule, pack: restored.pack, events: restored.events).verified)
    }
}
