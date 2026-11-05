import Foundation
import FSRS

public struct ReviewKey: Hashable, Identifiable, Codable {
    public let itemID: String
    public let skill: Skill
    public init(itemID: String, skill: Skill) { self.itemID = itemID; self.skill = skill }
    public var id: String { itemID + ":" + skill.rawValue }
}

public struct ScheduledItem: Identifiable {
    public let key: ReviewKey
    public let card: Card
    public var id: String { key.id }
}

public struct ReviewScheduler {
    private let scheduler = FSRS(parameters: FSRSParameters(
        requestRetention: 0.9, w: FSRSDefaults.defaultWv6, enableFuzz: false
    ))
    public init() {}

    public func replay(_ events: [LearningEvent]) throws -> [ReviewKey: Card] {
        var cards: [ReviewKey: Card] = [:]
        for event in events.sorted(by: LearningEvent.ordered) where event.kind == .review {
            try event.validate()
            guard let skill = event.skill, let ratingValue = event.rating,
                  let rating = Rating(rawValue: event.assisted ? 1 : ratingValue) else { continue }
            let key = ReviewKey(itemID: event.targetID, skill: skill)
            let current = cards[key] ?? Card(due: event.timestamp)
            cards[key] = try scheduler.next(card: current, now: event.timestamp, grade: rating).card
        }
        return cards
    }

    public func due(events: [LearningEvent], pack: ContentPack, now: Date = Date()) throws -> [ScheduledItem] {
        let available = Set(pack.items.flatMap { item in item.skills.map { ReviewKey(itemID: item.id, skill: $0) } })
        return try replay(events).compactMap { key, card in
            available.contains(key) && card.due <= now ? ScheduledItem(key: key, card: card) : nil
        }.sorted { $0.card.due == $1.card.due ? $0.id < $1.id : $0.card.due < $1.card.due }
    }
}

public enum SessionTask: Identifiable, Codable {
    case recall(ReviewKey)
    case exercise(String)
    case reading(String)
    public var id: String {
        switch self {
        case .recall(let key): return "recall:" + key.id
        case .exercise(let id): return "exercise:" + id
        case .reading(let id): return "reading:" + id
        }
    }
}

public enum SessionPlanner {
    public static func make(pack: ContentPack, events: [LearningEvent], minutes: Int,
                            now: Date = Date(), calendar: Calendar = .current) throws -> [SessionTask] {
        let capacity = max(1, min(minutes, 60) * 2)
        let scheduler = ReviewScheduler()
        let due = try scheduler.due(events: events, pack: pack, now: now)
        var tasks = due.prefix(capacity).map { item -> SessionTask in
            if item.key.skill == .grammar {
                let variations = pack.exercises.filter { $0.targetID == item.key.itemID }.sorted { $0.id < $1.id }
                if !variations.isEmpty {
                    return .exercise(variations[item.card.reps % variations.count].id)
                }
            }
            return .recall(item.key)
        }
        let cards = try scheduler.replay(events)
        let firstReviews = Dictionary(grouping: events.filter { $0.kind == .review }, by: \.targetID)
        let newToday = Set(firstReviews.compactMap { id, reviews -> String? in
            guard let first = reviews.min(by: LearningEvent.ordered), calendar.isDate(first.timestamp, inSameDayAs: now) else { return nil }
            return id
        })
        let wordSlots = max(0, 5 - newToday.filter { pack.item($0)?.kind == "word" }.count)
        let grammarSlots = max(0, 1 - newToday.filter { pack.item($0)?.kind == "grammar" }.count)
        if due.count < capacity / 2 {
            let unfinishedWords = pack.items.filter { item in
                item.kind == "word" && item.skills.contains { cards[ReviewKey(itemID: item.id, skill: $0)] != nil }
                && item.skills.contains { cards[ReviewKey(itemID: item.id, skill: $0)] == nil }
            }
            let newWords = pack.items.filter { item in
                item.kind == "word" && item.skills.allSatisfy { cards[ReviewKey(itemID: item.id, skill: $0)] == nil }
            }.prefix(wordSlots)
            for item in unfinishedWords + Array(newWords) {
                for skill in item.skills where cards[ReviewKey(itemID: item.id, skill: skill)] == nil {
                    tasks.append(.recall(ReviewKey(itemID: item.id, skill: skill)))
                }
            }
            if grammarSlots > 0,
               let exercise = pack.exercises.first(where: { cards[ReviewKey(itemID: $0.targetID, skill: .grammar)] == nil }) {
                // An unseen example follows the first exercise for the same structure.
                tasks.append(.exercise(exercise.id))
                if let transfer = pack.exercises.first(where: { $0.targetID == exercise.targetID && $0.transfer }) {
                    tasks.append(.exercise(transfer.id))
                }
            }
        }
        // Revisit passages in order, without making reading contingent on completing all cards.
        if let passage = pack.readings.first(where: { reading in
            !events.contains { $0.kind == .readingAttempt && $0.targetID == reading.id }
        }) ?? pack.readings.first {
            tasks = Array(tasks.prefix(max(0, capacity - 1)))
            tasks.append(.reading(passage.id))
        }
        return Array(tasks.prefix(capacity))
    }
}

public struct SessionEntry: Codable, Identifiable {
    public let id: UUID
    public let task: SessionTask
    public init(task: SessionTask) { id = UUID(); self.task = task }
}

public struct SessionCheckpoint: Codable {
    public let schemaVersion: Int
    public let id: UUID
    public let entries: [SessionEntry]
    public var index: Int
    public var assistedEntryIDs: Set<UUID>
    public let lessonID: String?
    public let startedAt: Date
    public init(tasks: [SessionTask], lessonID: String? = nil) {
        schemaVersion = 1; id = UUID(); entries = tasks.map { SessionEntry(task: $0) }; index = 0
        self.lessonID = lessonID; startedAt = Date(); assistedEntryIDs = []
    }
    public var current: SessionEntry? { entries.indices.contains(index) ? entries[index] : nil }
    public func validate() throws {
        guard schemaVersion == 1, (0...entries.count).contains(index),
              Set(entries.map(\.id)).count == entries.count,
              assistedEntryIDs.isSubset(of: Set(entries.map(\.id))) else {
            throw LearningError.invalid("上次学习安排无法恢复，已完成的学习记录仍保留。")
        }
    }
    public mutating func recover(recordedIDs: Set<UUID>) {
        while let entry = current, recordedIDs.contains(entry.id) { index += 1 }
    }
}
