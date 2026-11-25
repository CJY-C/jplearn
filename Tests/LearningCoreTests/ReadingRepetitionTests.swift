import XCTest
@testable import LearningCore

final class ReadingRepetitionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400
    private let device = UUID()
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func fixture() throws -> (ContentPack, ReadingPassage, [LearningEvent]) {
        let pack = try ContentPack.bundled()
        let reading = try XCTUnwrap(pack.readings.first { $0.id == "r009" })
        let words = Set((reading.vocabulary ?? []).compactMap(\.itemID))
        let events = words.map {
            LearningEvent(deviceID: device, timestamp: start, kind: .review, targetID: $0, skill: .meaning, rating: 3)
        } + (reading.grammarIDs ?? []).map {
            LearningEvent(deviceID: device, timestamp: start, kind: .review, targetID: $0, skill: .grammar, rating: 3)
        }
        return (pack, reading, events)
    }

    private func attempt(_ reading: ReadingPassage, after days: Double, correct: Bool = true,
                         assisted: Bool = false) -> LearningEvent {
        LearningEvent(deviceID: device, timestamp: start.addingTimeInterval(days * day),
            kind: .readingAttempt, targetID: reading.id, assisted: assisted, value: correct ? "correct" : "incorrect")
    }

    func testFamiliarMorningPassageGetsLongerSpacedRepetitionIntervals() throws {
        let (pack, reading, known) = try fixture()
        XCTAssertEqual(reading.title, "早晨的两个地方")
        var history = known
        func available(_ day: Double) -> Bool {
            SessionPlanner.readingAvailable(reading, pack: pack, events: history,
                now: start.addingTimeInterval(day * self.day), calendar: calendar)
        }
        XCTAssertTrue(available(0))
        history.append(attempt(reading, after: 0))
        XCTAssertFalse(available(0.9))
        XCTAssertTrue(available(1))
        history.append(attempt(reading, after: 1))
        XCTAssertFalse(available(2), "A second spaced success must stop the daily loop")
        XCTAssertTrue(available(4))
        history.append(attempt(reading, after: 4))
        XCTAssertFalse(available(7))
        XCTAssertTrue(available(11))
        history.append(attempt(reading, after: 11))
        XCTAssertFalse(available(18))
        XCTAssertTrue(available(25))
        history.append(attempt(reading, after: 25))
        XCTAssertFalse(available(39))
        XCTAssertTrue(available(55))

        let now = start.addingTimeInterval(26 * day)
        let blockedOthers = pack.readings.filter { $0.id != reading.id }.map {
            LearningEvent(deviceID: device, timestamp: now, kind: .readingAttempt, targetID: $0.id, value: "correct")
        }
        let tasks = try SessionPlanner.make(pack: pack, events: history + blockedOthers,
            minutes: 60, now: now, calendar: calendar, newWordLimit: 0, newGrammarLimit: 0)
        XCTAssertFalse(tasks.contains { if case .reading = $0 { return true }; return false },
            "A time goal must not fill spare time with a familiar passage before it is due")
    }

    func testFailedOrAssistedReadingResetsTheNextIndependentCheck() throws {
        let (pack, reading, known) = try fixture()
        let successes = [attempt(reading, after: 0), attempt(reading, after: 1)]
        for reset in [attempt(reading, after: 2, correct: false), attempt(reading, after: 2, assisted: true)] {
            let history = known + successes + [reset]
            XCTAssertFalse(SessionPlanner.readingAvailable(reading, pack: pack, events: history,
                now: start.addingTimeInterval(2.9 * day), calendar: calendar))
            XCTAssertTrue(SessionPlanner.readingAvailable(reading, pack: pack, events: history,
                now: start.addingTimeInterval(3 * day), calendar: calendar))
        }
    }

    func testSameDayCrammingDoesNotInventSpacedSuccesses() throws {
        let (pack, reading, known) = try fixture()
        let cramming = (0..<40).map { attempt(reading, after: Double($0) / 1_440) }
        let history = known + cramming
        XCTAssertFalse(SessionPlanner.readingAvailable(reading, pack: pack, events: history,
            now: start.addingTimeInterval(3_600), calendar: calendar))
        XCTAssertTrue(SessionPlanner.readingAvailable(reading, pack: pack, events: history,
            now: start.addingTimeInterval(2 * day), calendar: calendar),
            "Repeated success within one day cannot create a month-long interval")
    }

    func testMergedOrderDuplicatesAndFutureAttemptsCannotExtendTheInterval() throws {
        let (pack, reading, known) = try fixture()
        let first = attempt(reading, after: 0), second = attempt(reading, after: 1)
        let future = attempt(reading, after: 100)
        let histories = [known + [first, second], known + [future, second, first, second],
                         Array((known + [first, future, second]).reversed())]
        for history in histories {
            XCTAssertFalse(SessionPlanner.readingAvailable(reading, pack: pack, events: history,
                now: start.addingTimeInterval(2 * day), calendar: calendar))
            XCTAssertTrue(SessionPlanner.readingAvailable(reading, pack: pack, events: history,
                now: start.addingTimeInterval(4 * day), calendar: calendar))
        }
    }
}
