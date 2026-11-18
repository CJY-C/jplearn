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
}
