import XCTest
@testable import LearningCore

final class LearningStatisticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func review(_ id: String, _ skill: Skill, _ rating: Int = 3,
                        at date: Date? = nil, assisted: Bool = false) -> LearningEvent {
        LearningEvent(deviceID: UUID(), timestamp: date ?? now.addingTimeInterval(-60), kind: .review,
                      targetID: id, skill: skill, rating: rating, assisted: assisted)
    }

    func testProgressSeparatesMeaningReadingAndSharedPronunciation() throws {
        let pack = try ContentPack.bundled()
        let root = try XCTUnwrap(pack.item("vn6125"))
        let sense = try XCTUnwrap(pack.item("vn4962"))
        let events = [review(root.id, .meaning), review(sense.id, .meaning)]
        let first = try LearningStatistics.make(pack: pack, events: events, now: now)
        let level = try XCTUnwrap(first.levels.first { $0.id == "N4" })
        XCTAssertEqual(level.meaning.remembered, 1)
        XCTAssertEqual(first.levels.reduce(0) { $0 + $1.meaning.remembered }, 2)
        XCTAssertEqual(level.reading.remembered, 0)
        XCTAssertEqual(level.linkedWords, 0)
        let second = try LearningStatistics.make(pack: pack, events: events + [review(root.id, .reading)], now: now)
        let linked = try XCTUnwrap(second.levels.first { $0.id == "N4" })
        XCTAssertEqual(linked.reading.remembered, 0, "The shared reading belongs to its original N5 word")
        XCTAssertEqual(linked.linkedWords, 1)
        XCTAssertEqual(second.levels.reduce(0) { $0 + $1.linkedWords }, 2)
        XCTAssertEqual(second.forecasts.first { $0.skill == .reading }?.cardCount, 1)
    }

    func testLatestForgettingAndAssistanceReduceProgressWithoutErasingPractice() throws {
        let pack = try ContentPack.bundled()
        let events = [review("v0001", .meaning), review("v0002", .meaning),
            review("v0001", .meaning, 1, at: now.addingTimeInterval(-1)),
            review("v0002", .meaning, 4, at: now.addingTimeInterval(-1), assisted: true),
            review("v0003", .meaning, 2)]
        let stats = try LearningStatistics.make(pack: pack, events: events, now: now)
        let level = try XCTUnwrap(stats.levels.first { $0.id == "N5" })
        XCTAssertEqual(level.meaning.practiced, 3)
        XCTAssertEqual(level.meaning.remembered, 0)
        XCTAssertEqual(stats.independentRecallCount, 3, "Effortful independent recall counts as recalled, but not confidently remembered")
        XCTAssertEqual(stats.recallRate, 0.6)
    }

    func testMergedHistoryAndLocalMidnightDoNotInflateStatistics() throws {
        let pack = try ContentPack.bundled()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let midnight = calendar.startOfDay(for: now)
        let first = LearningEvent(deviceID: UUID(), timestamp: midnight.addingTimeInterval(30), kind: .studyTime,
                                  targetID: UUID().uuidString, durationSeconds: 60)
        let overlap = LearningEvent(deviceID: UUID(), timestamp: midnight.addingTimeInterval(50), kind: .studyTime,
                                    targetID: UUID().uuidString, durationSeconds: 40)
        let valid = review("v0001", .meaning)
        let stats = try LearningStatistics.make(pack: pack, events: [first, first, overlap, valid, valid,
            review("missing", .meaning), review("v0001", .grammar),
            review("v0002", .meaning, at: now.addingTimeInterval(100))], now: now, calendar: calendar)
        XCTAssertEqual(stats.totalSeconds, 80, accuracy: 0.001)
        XCTAssertEqual(stats.days.last?.seconds, 50)
        XCTAssertEqual(stats.days.dropLast().last?.seconds, 30)
        XCTAssertEqual(stats.activeDays, 2)
        XCTAssertEqual(stats.reviewCount, 1)
        XCTAssertEqual(stats.forecasts.first { $0.skill == .meaning }?.cardCount, 1)
        XCTAssertTrue(stats.forecasts.first { $0.skill == .grammar }?.points.isEmpty == true)
    }

    func testForecastUsesIndependentSkillsAndFallsWithoutReview() throws {
        let pack = try ContentPack.bundled()
        let history = [review("v0001", .reading, at: now.addingTimeInterval(-5 * 86_400)),
                       review("v0001", .reading, 4, at: now.addingTimeInterval(-86_400))]
        let stats = try LearningStatistics.make(pack: pack, events: history, now: now)
        let curve = try XCTUnwrap(stats.forecasts.first { $0.skill == .reading })
        XCTAssertEqual(curve.points.map(\.day), [0, 1, 3, 7, 14, 30])
        for (a, b) in zip(curve.points, curve.points.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.probability, b.probability)
            XCTAssertTrue((0...1).contains(b.probability))
        }
        XCTAssertGreaterThan(curve.points[0].probability, curve.points[5].probability)
        let updated = try LearningStatistics.make(pack: pack,
            events: history + [review("v0001", .reading, 4, at: now)], now: now)
        let refreshed = try XCTUnwrap(updated.forecasts.first { $0.skill == .reading })
        XCTAssertGreaterThan(refreshed.points[0].probability, curve.points[0].probability)
        XCTAssertTrue(stats.forecasts.first { $0.skill == .meaning }?.points.isEmpty == true)
    }

    func testEmptyHistoryAndUnavailableLevelHaveNoInventedProgress() throws {
        let stats = try LearningStatistics.make(pack: ContentPack.bundled(), events: [], now: now)
        XCTAssertNil(stats.recallRate)
        XCTAssertEqual(stats.totalSeconds, 0)
        XCTAssertEqual(stats.activeDays, 0)
        XCTAssertTrue(stats.forecasts.allSatisfy { $0.points.isEmpty })
        let n2 = try XCTUnwrap(stats.levels.first { $0.id == "N2" })
        XCTAssertEqual(n2.meaning.total, 0)
        XCTAssertEqual(n2.meaning.fraction, 0)
    }
}
