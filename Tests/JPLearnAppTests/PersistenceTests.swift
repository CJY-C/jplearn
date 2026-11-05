import XCTest
import LearningCore
@testable import JPLearn

final class PersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func event() -> LearningEvent {
        LearningEvent(deviceID: UUID(), kind: .review, targetID: "v0001", skill: .reading, rating: 3)
    }

    @MainActor func testJournalSurvivesReopeningAndDuplicateImport() throws {
        let folder = try directory()
        let first = try EventStore(directory: folder)
        let original = event()
        let saved = try first.append([original], existing: [])
        _ = try first.append([original], existing: saved)
        let second = try EventStore(directory: folder)
        XCTAssertEqual(try second.load(), [original])
    }

    @MainActor func testInvalidBatchDoesNotPartiallyCommit() throws {
        let store = try EventStore(directory: directory())
        let original = event()
        let saved = try store.append([original], existing: [])
        let invalid = LearningEvent(deviceID: UUID(), kind: .review, targetID: "v0002", skill: .reading, rating: 9)
        XCTAssertThrowsError(try store.append([event(), invalid], existing: saved))
        XCTAssertEqual(try store.load(), [original])
    }

    func testTwoDevicesExchangeOfflineAnswersWithoutOverwriting() throws {
        let folder = try directory()
        let a = event(), b = event()
        let first = try FolderExchange.exchange(directory: folder, events: [a], contentVersion: "test")
        XCTAssertEqual(first.written, 1)
        let second = try FolderExchange.exchange(directory: folder, events: [b], contentVersion: "test")
        XCTAssertEqual(second.events.count, 2)
        let third = try FolderExchange.exchange(directory: folder, events: first.events, contentVersion: "test")
        XCTAssertEqual(third.events, second.events)
        XCTAssertEqual(third.written, 0)
        let again = try FolderExchange.exchange(directory: folder, events: third.events, contentVersion: "test")
        XCTAssertEqual(again.events.count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }

    func testCorruptFileDoesNotPublishAnotherBatch() throws {
        let folder = try directory()
        try Data("partial".utf8).write(to: folder.appendingPathComponent("damaged.jplearnsync"))
        XCTAssertThrowsError(try FolderExchange.exchange(directory: folder, events: [event()], contentVersion: "test"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["damaged.jplearnsync"])
    }
}
