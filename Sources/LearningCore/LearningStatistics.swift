import Foundation

public struct LearningProgress {
    public let total: Int
    public let practiced: Int
    public let remembered: Int
    public var fraction: Double { total == 0 ? 0 : Double(remembered) / Double(total) }
}

public struct LevelProgress: Identifiable {
    public let id: String
    public let meaning: LearningProgress
    public let reading: LearningProgress
    public let grammar: LearningProgress
    public let passages: LearningProgress
    public let linkedWords: Int
}

public struct DailyStudy: Identifiable {
    public let date: Date
    public let seconds: TimeInterval
    public let reviews: Int
    public var id: Date { date }
}

public struct RetentionPoint {
    public let day: Int
    public let probability: Double
}

public struct RetentionForecast: Identifiable {
    public let skill: Skill
    public let cardCount: Int
    public let points: [RetentionPoint]
    public var id: Skill { skill }
}

/// Derived from the journal, so import and iCloud merge need no new sync format.
public struct LearningStatistics {
    public let totalSeconds: TimeInterval
    public let activeDays: Int
    public let reviewCount: Int
    public let independentRecallCount: Int
    public let dueCount: Int
    public let days: [DailyStudy]
    public let levels: [LevelProgress]
    public let forecasts: [RetentionForecast]
    public var recallRate: Double? {
        reviewCount == 0 ? nil : Double(independentRecallCount) / Double(reviewCount)
    }

    public static func make(pack: ContentPack, events: [LearningEvent], now: Date = Date(),
                            calendar: Calendar = .current) throws -> Self {
        let history = try EventMerge.merge([], events).filter { $0.timestamp <= now }
        let available = Set(pack.items.flatMap { item in item.skills.map { ReviewKey(itemID: item.id, skill: $0) } })
        let reviews = history.filter { event in
            guard event.kind == .review, let skill = event.skill else { return false }
            return available.contains(ReviewKey(itemID: event.targetID, skill: skill))
        }
        let latest = reviews.reduce(into: [ReviewKey: LearningEvent]()) { result, event in
            if let skill = event.skill { result[ReviewKey(itemID: event.targetID, skill: skill)] = event }
        }
        func remembered(_ key: ReviewKey) -> Bool {
            guard let event = latest[key] else { return false }
            return !event.assisted && (event.rating ?? 0) >= 3
        }
        func progress(_ items: [KnowledgeItem], _ skill: Skill) -> LearningProgress {
            let keys = items.filter { $0.skills.contains(skill) }.map { ReviewKey(itemID: $0.id, skill: skill) }
            return LearningProgress(total: keys.count, practiced: keys.filter { latest[$0] != nil }.count,
                                    remembered: keys.filter(remembered).count)
        }
        let passageIDs = Set(pack.readings.map(\.id))
        let attempts = history.filter { $0.kind == .readingAttempt && passageIDs.contains($0.targetID) }
        let lastAttempts = attempts.reduce(into: [String: LearningEvent]()) { $0[$1.targetID] = $1 }
        let levels = ["N5", "N4", "N3", "N2"].map { level -> LevelProgress in
            let items = pack.items.filter { $0.level == level }
            let passages = pack.readings.filter { $0.level == level }
            return LevelProgress(id: level, meaning: progress(items, .meaning), reading: progress(items, .reading),
                grammar: progress(items, .grammar),
                passages: LearningProgress(total: passages.count,
                    practiced: passages.filter { lastAttempts[$0.id] != nil }.count,
                    remembered: passages.filter { lastAttempts[$0.id]?.value == "correct" && lastAttempts[$0.id]?.assisted == false }.count),
                linkedWords: items.filter { item in
                    item.kind == "word" && remembered(ReviewKey(itemID: item.id, skill: .meaning)) &&
                        remembered(ReviewKey(itemID: item.readingOwnerID ?? item.id, skill: .reading))
                }.count)
        }
        let times = history.filter { $0.kind == .studyTime }
        var active = Set((reviews + attempts).map { calendar.startOfDay(for: $0.timestamp) })
        for event in times {
            let start = event.timestamp.addingTimeInterval(-(event.durationSeconds ?? 0))
            var day = calendar.startOfDay(for: start)
            while day < event.timestamp {
                active.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
            }
        }
        let today = calendar.startOfDay(for: now)
        let days = (-29...0).compactMap { offset -> DailyStudy? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
            return DailyStudy(date: day, seconds: StudyTime.seconds(events: times, within: interval),
                              reviews: reviews.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }.count)
        }
        let scheduler = ReviewScheduler()
        let cards = try scheduler.replay(reviews)
        let forecasts = Skill.allCases.map { skill -> RetentionForecast in
            let selected = cards.keys.filter { $0.skill == skill }.sorted { $0.id < $1.id }
            let points = selected.isEmpty ? [] : [0, 1, 3, 7, 14, 30].map { day -> RetentionPoint in
                let date = now.addingTimeInterval(Double(day) * 86_400)
                let mean = selected.reduce(0.0) { sum, key in
                    guard let card = cards[key] else { return sum }
                    return sum + scheduler.retrievability(card: card, at: date)
                } / Double(selected.count)
                return RetentionPoint(day: day, probability: min(1, max(0, mean)))
            }
            return RetentionForecast(skill: skill, cardCount: selected.count, points: points)
        }
        return Self(totalSeconds: StudyTime.seconds(events: times), activeDays: active.count,
                    reviewCount: reviews.count,
                    independentRecallCount: reviews.filter { !$0.assisted && ($0.rating ?? 0) >= 2 }.count,
                    dueCount: scheduler.due(cards: cards, pack: pack, now: now).count,
                    days: days, levels: levels, forecasts: forecasts)
    }
}
