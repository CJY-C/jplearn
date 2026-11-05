import XCTest
@testable import LearningCore

final class StudyTimeTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = UUID()
    private func event(start: Date, seconds: TimeInterval, device: UUID = UUID()) -> LearningEvent {
        LearningEvent(deviceID: device, timestamp: start.addingTimeInterval(seconds), kind: .studyTime,
                      targetID: session.uuidString, durationSeconds: seconds)
    }

    func testElapsedTimeUsesUptimeAndExcludesAPause() {
        var clock = StudyTimeAccumulator()
        XCTAssertTrue(clock.start(at: date, uptime: 100))
        clock.sample(uptime: 120)
        clock.stop(uptime: 125)
        XCTAssertEqual(clock.pendingSeconds, 25)
        XCTAssertEqual(clock.pendingInterval?.duration, 25)
        XCTAssertFalse(clock.start(at: date.addingTimeInterval(3600), uptime: 3700))
        clock.acknowledgePending()
        XCTAssertTrue(clock.start(at: date.addingTimeInterval(3600), uptime: 3700))
        clock.stop(uptime: 3710)
        XCTAssertEqual(clock.elapsedSeconds, 35)
        XCTAssertEqual(clock.pendingSeconds, 10)
        XCTAssertEqual(clock.pendingInterval?.start, date.addingTimeInterval(3600))
    }

    func testSamplesWhileStoppedAndRegressingClocksDoNotAddTime() {
        var clock = StudyTimeAccumulator()
        clock.sample(uptime: 1000)
        XCTAssertEqual(clock.elapsedSeconds, 0)
        _ = clock.start(at: date, uptime: 100)
        clock.sample(uptime: 90)
        clock.sample(uptime: 110)
        XCTAssertEqual(clock.elapsedSeconds, 10)
    }

    func testPersistAcknowledgementKeepsRunningIntervalsContinuous() {
        var clock = StudyTimeAccumulator()
        _ = clock.start(at: date, uptime: 100)
        clock.sample(uptime: 115)
        clock.acknowledgePending()
        clock.stop(uptime: 120)
        XCTAssertEqual(clock.pendingInterval?.start, date.addingTimeInterval(15))
        XCTAssertEqual(clock.pendingSeconds, 5)
        XCTAssertEqual(clock.elapsedSeconds, 20)
    }

    func testMultipleDevicesAndDuplicateBackupsDoNotDoubleCountTime() throws {
        let a = event(start: date, seconds: 60)
        let b = event(start: date.addingTimeInterval(30), seconds: 60)
        let merged = try EventMerge.merge([a], [a, b])
        XCTAssertEqual(StudyTime.seconds(events: merged), 90, accuracy: 0.001)
        let live = DateInterval(start: date.addingTimeInterval(80), duration: 20)
        XCTAssertEqual(StudyTime.seconds(events: merged, live: live), 100, accuracy: 0.001)
    }

    func testTimingSplitsAtLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let midnight = calendar.startOfDay(for: date)
        let record = event(start: midnight.addingTimeInterval(-20), seconds: 50)
        XCTAssertEqual(StudyTime.today(events: [record], now: midnight.addingTimeInterval(100), calendar: calendar), 30, accuracy: 0.001)
        XCTAssertEqual(StudyTime.today(events: [record], now: midnight.addingTimeInterval(-1), calendar: calendar), 20, accuracy: 0.001)
    }

    func testDailyGoalUsesAccumulatedTime() {
        XCTAssertEqual(StudyTime.remainingSeconds(targetMinutes: 20, studiedSeconds: 180), 1020)
        XCTAssertEqual(StudyTime.remainingSeconds(targetMinutes: 20, studiedSeconds: 1500), 0)
        XCTAssertEqual(StudyTime.clock(125), "02:05")
        XCTAssertEqual(StudyTime.clock(3661), "1:01:01")
    }

    func testStudyTimeSurvivesBackupRoundTrip() throws {
        let original = event(start: date, seconds: 17.125)
        let data = try ArchiveCodec.encode(ExchangeArchive(events: [original], contentVersion: "test"))
        let decoded = try ArchiveCodec.decode(data)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.events, [original])
        XCTAssertEqual(StudyTime.seconds(events: decoded.events), 17.125, accuracy: 0.001)
    }

    func testLegacyEventsAndVersionOneBackupStillImport() throws {
        let old = LearningEvent(deviceID: UUID(), timestamp: date, kind: .review, targetID: "v0001", skill: .reading, rating: 3)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: ExchangeArchive(events: [old], contentVersion: "0.1.0").encoded()) as? [String: Any])
        payload["schemaVersion"] = 1
        var rows = try XCTUnwrap(payload["events"] as? [[String: Any]])
        rows[0].removeValue(forKey: "durationSeconds")
        payload["events"] = rows
        let restored = try ExchangeArchive.decode(JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(restored.events, [old])
        XCTAssertEqual(StudyTime.seconds(events: restored.events), 0)
    }

    func testInvalidDurationsAreRejectedBeforeImport() {
        for seconds in [-1.0, 0, Double.infinity, Double.nan, 100_000] {
            XCTAssertThrowsError(try event(start: date, seconds: seconds).validate())
        }
    }
}
