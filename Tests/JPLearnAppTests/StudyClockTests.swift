import XCTest
import LearningCore
@testable import JPLearn

final class StudyClockTests: XCTestCase {
    @MainActor func testBackgroundAndManualPauseDoNotAccumulateTime() throws {
        var uptime: TimeInterval = 100
        var wall = Date(timeIntervalSince1970: 1_800_000_000)
        var intervals: [DateInterval] = []
        let clock = StudyClock(automaticallyTicks: false, now: { wall }, uptime: { uptime })
        clock.onInterval = { _, interval in intervals.append(interval) }
        try clock.bind(sessionID: UUID(), recordedSeconds: 12)
        try clock.setVisible(true)
        uptime += 10; wall.addTimeInterval(10)
        try clock.setForeground(false)
        XCTAssertEqual(clock.elapsedSeconds, 22)
        uptime += 600; wall.addTimeInterval(600)
        try clock.setForeground(true)
        uptime += 5; wall.addTimeInterval(5)
        try clock.pause()
        XCTAssertEqual(clock.elapsedSeconds, 27)
        uptime += 600; wall.addTimeInterval(600)
        try clock.setForeground(false); try clock.setForeground(true)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsedSeconds, 27)
        try clock.resume()
        uptime += 3; wall.addTimeInterval(3)
        try clock.setVisible(false)
        XCTAssertEqual(clock.elapsedSeconds, 30)
        XCTAssertEqual(intervals.reduce(0) { $0 + $1.duration }, 18, accuracy: 0.001)
    }

    @MainActor func testFailedPersistenceRetainsPendingTimeForRetry() throws {
        var uptime: TimeInterval = 100
        var fail = true
        var saved: TimeInterval = 0
        let clock = StudyClock(automaticallyTicks: false, uptime: { uptime })
        clock.onInterval = { _, interval in
            if fail { throw LearningError.invalid("test failure") }
            saved += interval.duration
        }
        try clock.bind(sessionID: UUID(), recordedSeconds: 0)
        try clock.setVisible(true)
        uptime += 20
        XCTAssertThrowsError(try clock.flush())
        XCTAssertTrue(clock.isManuallyPaused)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.pendingInterval?.duration, 20)
        fail = false
        try clock.resume()
        uptime += 5
        try clock.setVisible(false)
        XCTAssertEqual(saved, 25, accuracy: 0.001)
        XCTAssertEqual(clock.elapsedSeconds, 25)
    }
}
