import Foundation
import FSRS

public struct ReviewKey: Hashable, Identifiable, Codable {
    public let itemID: String
    public let skill: Skill
    public init(itemID: String, skill: Skill) { self.itemID = itemID; self.skill = skill }
    public var id: String { itemID + ":" + skill.rawValue }
}

struct ScheduledItem: Identifiable {
    let key: ReviewKey
    let card: Card
    var id: String { key.id }
}

public struct ReviewScheduler {
    private let scheduler = FSRS(parameters: FSRSParameters(
        requestRetention: 0.9, w: FSRSDefaults.defaultWv6, enableFuzz: false
    ))
    public init() {}

    func retrievability(card: Card, at date: Date) -> Double {
        scheduler.getRetrievability(card: card, now: date).number
    }

    public func validateHistory(_ events: [LearningEvent]) throws {
        _ = try replay(events)
    }

    public func dueKeys(events: [LearningEvent], pack: ContentPack, now: Date = Date()) throws -> [ReviewKey] {
        try due(events: events, pack: pack, now: now).map(\.key)
    }

    func replay(_ events: [LearningEvent]) throws -> [ReviewKey: Card] {
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

    func due(events: [LearningEvent], pack: ContentPack, now: Date = Date()) throws -> [ScheduledItem] {
        due(cards: try replay(events), pack: pack, now: now,
            consolidated: RuleKnowledge(pack: pack, events: events, now: now).consolidatedKeys)
    }

    func due(cards: [ReviewKey: Card], pack: ContentPack, now: Date,
             consolidated: Set<ReviewKey> = []) -> [ScheduledItem] {
        let available = Set(pack.items.flatMap { item in item.skills.map { ReviewKey(itemID: item.id, skill: $0) } })
        return cards.compactMap { key, card in
            available.contains(key) && !consolidated.contains(key) && card.due <= now ? ScheduledItem(key: key, card: card) : nil
        }.sorted { $0.card.due == $1.card.due ? $0.id < $1.id : $0.card.due < $1.card.due }
    }
}

public enum SessionTask: Identifiable, Codable {
    case recall(ReviewKey)
    case exercise(String)
    case reading(String)
    case rule(String)
    public var id: String {
        switch self {
        case .recall(let key): return "recall:" + key.id
        case .exercise(let id): return "exercise:" + id
        case .reading(let id): return "reading:" + id
        case .rule(let id): return "rule:" + id
        }
    }
}

// Passage repetition is separate from word/grammar FSRS. A correct answer to a
// familiar passage does not demonstrate transfer to a new text or its words.
private struct ReadingReviewState {
    var lastAttempt: Date
    var nextDue: Date
    var spacedSuccesses: Int

    static func history(_ events: [LearningEvent], now: Date) -> [String: ReadingReviewState] {
        // A bounded product policy, not an estimated forgetting curve.
        let intervals = [1, 3, 7, 14, 30].map { TimeInterval($0) * 86_400 }
        let attempts = events.filter { $0.kind == .readingAttempt && $0.timestamp <= now }
            .sorted(by: LearningEvent.ordered)
        var result: [String: ReadingReviewState] = [:]
        for event in attempts {
            let previous = result[event.targetID]
            var state = previous ?? ReadingReviewState(lastAttempt: event.timestamp,
                nextDue: event.timestamp, spacedSuccesses: 0)
            state.lastAttempt = event.timestamp
            if event.value != "correct" || event.assisted {
                state.spacedSuccesses = 0
                state.nextDue = event.timestamp.addingTimeInterval(intervals[0])
            } else if previous == nil || event.timestamp >= state.nextDue {
                state.spacedSuccesses = min(intervals.count, state.spacedSuccesses + 1)
                state.nextDue = event.timestamp.addingTimeInterval(intervals[state.spacedSuccesses - 1])
            }
            // Early manual repetitions neither count as spaced successes nor
            // postpone the next independent check. The daily cooldown still applies.
            result[event.targetID] = state
        }
        return result
    }
}

public enum SessionPlanner {
    public static func make(pack: ContentPack, events: [LearningEvent], minutes: Int,
                            now: Date = Date(), calendar: Calendar = .current,
                            newWordLimit: Int = 10, newGrammarLimit: Int = 2) throws -> [SessionTask] {
        let capacity = max(1, min(minutes, 60) * 2)
        let scheduler = ReviewScheduler()
        let rules = RuleKnowledge(pack: pack, events: events, now: now)
        let knowledge = ReadingKnowledge(events: events, inferredKeys: rules.consolidatedKeys, ruleProgress: rules.progress)
        // Both due selection and new-skill selection use the same replay of this
        // immutable history. Replaying FSRS again adds work, not information.
        let cards = try scheduler.replay(events)
        let due = scheduler.due(cards: cards, pack: pack, now: now, consolidated: rules.consolidatedKeys)
        var tasks = due.prefix(capacity).map { item -> SessionTask in
            if item.key.skill == .grammar || (item.key.skill == .meaning && item.card.reps % 2 == 0) {
                let variations = pack.exercises.filter { $0.targetID == item.key.itemID && ($0.skill ?? .grammar) == item.key.skill }.sorted { $0.id < $1.id }
                if !variations.isEmpty {
                    return .exercise(variations[item.card.reps % variations.count].id)
                }
            }
            return .recall(item.key)
        }
        let firstReviews = Dictionary(grouping: events.filter { $0.kind == .review }, by: \.targetID)
        let newToday = Set(firstReviews.compactMap { id, reviews -> String? in
            guard let first = reviews.min(by: LearningEvent.ordered), calendar.isDate(first.timestamp, inSameDayAs: now) else { return nil }
            return id
        })
        let wordSlots = max(0, min(20, max(0, newWordLimit)) - newToday.filter { pack.item($0)?.kind == "word" }.count)
        let grammarSlots = max(0, min(3, max(0, newGrammarLimit)) - newToday.filter { pack.item($0)?.kind == "grammar" }.count)
        if tasks.count < capacity,
           let rule = (pack.learningRules ?? []).first(where: { rule in
               guard let state = rules.progress[rule.id], rules.ready(rule) else { return false }
               return state.nextDue.map { $0 <= now } ?? true
           }), let state = rules.progress[rule.id] {
            tasks.append(.rule(state.nextSetID))
        }
        if due.count < capacity / 2 {
            let unfinishedWords = pack.items.filter { item in
                item.kind == "word" && item.skills.contains { cards[ReviewKey(itemID: item.id, skill: $0)] != nil }
                && item.skills.contains { cards[ReviewKey(itemID: item.id, skill: $0)] == nil &&
                    !rules.consolidatedKeys.contains(ReviewKey(itemID: item.id, skill: $0)) }
            }
            func comesFirst(_ a: KnowledgeItem, _ b: KnowledgeItem) -> Bool {
                let order = ["N5": 0, "N4": 1, "N3": 2, "N2": 3]
                let x = order[a.level] ?? 4, y = order[b.level] ?? 4
                if x != y { return x < y }
                let aOrder = a.order ?? Int.max, bOrder = b.order ?? Int.max
                return aOrder == bOrder ? a.id < b.id : aOrder < bOrder
            }
            func ready(_ item: KnowledgeItem) -> Bool {
                (item.prerequisiteIDs ?? []).allSatisfy { id in
                    knowledge.canApply(id, pack.item(id)?.kind == "word" ? .meaning : .grammar)
                }
            }
            let newWords = pack.items.filter { item in
                item.kind == "word" && item.skills.allSatisfy { cards[ReviewKey(itemID: item.id, skill: $0)] == nil }
                && item.skills.contains { !rules.consolidatedKeys.contains(ReviewKey(itemID: item.id, skill: $0)) }
                && ready(item)
            }.sorted(by: comesFirst).prefix(wordSlots)
            // Separate the two skills with other words instead of showing the same word twice in succession.
            for skill in [Skill.reading, .meaning] {
                for item in unfinishedWords + Array(newWords) where item.skills.contains(skill) && cards[ReviewKey(itemID: item.id, skill: skill)] == nil &&
                    !rules.consolidatedKeys.contains(ReviewKey(itemID: item.id, skill: skill)) {
                    tasks.append(.recall(ReviewKey(itemID: item.id, skill: skill)))
                }
            }
            let newGrammar = pack.items.filter {
                $0.kind == "grammar" && cards[ReviewKey(itemID: $0.id, skill: .grammar)] == nil
                && ready($0)
            }.sorted(by: comesFirst).prefix(grammarSlots)
            for item in newGrammar {
                // An unseen example follows the first exercise for the same structure.
                if let exercise = pack.exercises.first(where: { $0.targetID == item.id && !$0.transfer }) {
                    tasks.append(.exercise(exercise.id))
                }
                if let transfer = pack.exercises.first(where: { $0.targetID == item.id && $0.transfer }) {
                    tasks.append(.exercise(transfer.id))
                }
            }
        }
        // Never fall back to the first passage to fill a time goal.
        // Suitable unseen readings come first; spaced rereading is allowed on a later day.
        let readingHistory = ReadingReviewState.history(events, now: now)
        let candidates = pack.readings.filter {
            readingAvailable($0, pack: pack, knowledge: knowledge, history: readingHistory[$0.id],
                             now: now, calendar: calendar, includeAssessments: false)
        }.sorted { a, b in
            let aLast = readingHistory[a.id]?.lastAttempt, bLast = readingHistory[b.id]?.lastAttempt
            if aLast != bLast { return (aLast ?? .distantPast) < (bLast ?? .distantPast) }
            let aLength = a.vocabulary?.count ?? Int.max, bLength = b.vocabulary?.count ?? Int.max
            return aLength == bLength ? a.id < b.id : aLength < bLength
        }
        if let passage = candidates.first {
            tasks = Array(tasks.prefix(max(0, capacity - 1)))
            tasks.append(.reading(passage.id))
        }
        var seen = Set<String>()
        return Array(tasks.filter { seen.insert($0.id).inserted }.prefix(capacity))
    }

    public static func readingAvailable(_ reading: ReadingPassage, pack: ContentPack,
                                        events: [LearningEvent], now: Date = Date(),
                                        calendar: Calendar = .current, knowledge: ReadingKnowledge? = nil,
                                        includeAssessments: Bool = false) -> Bool {
        let history = ReadingReviewState.history(events.filter { $0.targetID == reading.id }, now: now)[reading.id]
        return readingAvailable(reading, pack: pack, knowledge: knowledge ?? ReadingKnowledge(pack: pack, events: events, now: now),
                                history: history, now: now, calendar: calendar,
                                includeAssessments: includeAssessments)
    }

    private static func readingAvailable(_ reading: ReadingPassage, pack: ContentPack,
                                         knowledge: ReadingKnowledge, history: ReadingReviewState?,
                                         now: Date, calendar: Calendar, includeAssessments: Bool) -> Bool {
        guard includeAssessments || reading.purpose != "assessment" else { return false }
        if let history = history {
            if calendar.isDate(history.lastAttempt, inSameDayAs: now) ||
                now.timeIntervalSince(history.lastAttempt) < 86_400 || history.nextDue > now {
                return false
            }
        }
        return ReadingReadiness.assess(reading, pack: pack, knowledge: knowledge).isEligible
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
    public private(set) var entries: [SessionEntry]
    public var index: Int
    public var assistedEntryIDs: Set<UUID>
    public let lessonID: String?
    public let startedAt: Date
    public var questionIndex: Int?
    public private(set) var ruleStudyModes: [String: RuleStudyMode]?
    public init(tasks: [SessionTask], lessonID: String? = nil) {
        schemaVersion = 1; id = UUID(); entries = tasks.map { SessionEntry(task: $0) }; index = 0
        self.lessonID = lessonID; startedAt = Date(); assistedEntryIDs = []
    }
    public var current: SessionEntry? { entries.indices.contains(index) ? entries[index] : nil }
    public func ruleStudyMode(for entryID: UUID) -> RuleStudyMode? {
        ruleStudyModes?[entryID.uuidString]
    }
    public mutating func selectRuleStudyMode(_ mode: RuleStudyMode, entryID: UUID) throws {
        guard let entry = current, entry.id == entryID, case .rule = entry.task else {
            throw LearningError.invalid("当前不是这组规则练习。")
        }
        if mode == .learn { assistedEntryIDs.insert(entryID) }
        if ruleStudyModes == nil { ruleStudyModes = [:] }
        ruleStudyModes?[entryID.uuidString] = mode
    }
    public func validate() throws {
        guard schemaVersion == 1, (0...entries.count).contains(index),
              (0...4).contains(questionIndex ?? 0),
              Set(entries.map(\.id)).count == entries.count,
              assistedEntryIDs.isSubset(of: Set(entries.map(\.id))) else {
            throw LearningError.invalid("上次学习安排无法恢复，已完成的学习记录仍保留。")
        }
        for (key, mode) in ruleStudyModes ?? [:] {
            guard let entry = entries.first(where: { $0.id.uuidString == key }),
                  case .rule = entry.task,
                  mode != .learn || assistedEntryIDs.contains(entry.id) else {
                throw LearningError.invalid("规则练习状态无法恢复，已完成的学习记录仍保留。")
            }
        }
    }
    public mutating func recover(recordedIDs: Set<UUID>) {
        while let entry = current, recordedIDs.contains(entry.id) { index += 1 }
    }
    public mutating func removeUnavailableReadings(pack: ContentPack, events: [LearningEvent], now: Date = Date()) {
        var seenReadings = Set(entries.prefix(index).compactMap { entry -> String? in
            if case .reading(let id) = entry.task { return id }; return nil
        })
        entries = Array(entries.prefix(index)) + entries.dropFirst(index).filter { entry in
            guard case .reading(let id) = entry.task else { return true }
            guard seenReadings.insert(id).inserted else { return false }
            guard let reading = pack.readings.first(where: { $0.id == id }) else { return false }
            if reading.purpose == "assessment" {
                return !events.contains { $0.kind == .readingAttempt && $0.targetID == id }
            }
            return SessionPlanner.readingAvailable(reading, pack: pack, events: events, now: now, includeAssessments: true)
        }
        assistedEntryIDs.formIntersection(Set(entries.map(\.id)))
        let retainedIDs = Set(entries.map { $0.id.uuidString })
        ruleStudyModes = ruleStudyModes?.filter { retainedIDs.contains($0.key) }
    }
}
