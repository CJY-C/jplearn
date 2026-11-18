import Foundation

/// Productive rules have their own evidence. Their examples never become invented word reviews.
public struct RulePracticeSet: Codable, Identifiable {
    public let id: String
    public let questions: [ReadingQuestion]
}

public struct LearningRule: Codable, Identifiable {
    public let id: String
    public let title: String
    public let explanation: String
    public let examples: [String]
    public let exceptions: [String]
    public let prerequisiteIDs: [String]
    public let prerequisiteRuleIDs: [String]
    /// Only author-checked, regular combinations. Exceptions and lexicalized words stay independent.
    public let regularItemIDs: [String]
    public let practiceSets: [RulePracticeSet]
    public let citations: [ContentCitation]
}

/// One immutable projection per plan, instead of repeatedly sorting the whole journal for every rule.
fileprivate struct RuleEvidence {
    let attempts: [String: [LearningEvent]]
    let answers: [String: [LearningEvent]]
    let reviews: [ReviewKey: LearningEvent]
    let directKnowledge: ReadingKnowledge

    init(events: [LearningEvent], now: Date) {
        let history = events.filter { $0.timestamp <= now && [.review, .placement, .questionAttempt].contains($0.kind) }
            .sorted(by: LearningEvent.ordered)
        attempts = Dictionary(grouping: history.filter { $0.kind == .placement }, by: \.targetID)
        answers = Dictionary(grouping: history.filter { $0.kind == .questionAttempt }, by: { $0.contextID ?? "" })
        reviews = history.reduce(into: [ReviewKey: LearningEvent]()) { result, event in
            if event.kind == .review, let skill = event.skill { result[ReviewKey(itemID: event.targetID, skill: skill)] = event }
        }
        directKnowledge = ReadingKnowledge(events: history)
    }
}

public struct RuleProgress {
    public let successfulSets: Int
    public let verified: Bool
    public let lastAttempt: Date?
    public let nextDue: Date?
    public let nextSetID: String
    public let consolidatedKeys: Set<ReviewKey>
    /// Correct, unassisted questions in completed successful sets since the last failed round.
    public let confirmedQuestionIDs: Set<String>

    public var title: String {
        verified ? "已验证迁移" : (successfulSets > 0 ? "等待隔天复测" : "待学习与验证")
    }

    public static func make(_ rule: LearningRule, pack: ContentPack, events: [LearningEvent],
                            now: Date = Date()) -> Self {
        make(rule, pack: pack, evidence: RuleEvidence(events: events, now: now))
    }

    fileprivate static func make(_ rule: LearningRule, pack: ContentPack, evidence: RuleEvidence) -> Self {
        let sets = Dictionary(uniqueKeysWithValues: rule.practiceSets.map { ($0.id, $0) })
        let attempts = rule.practiceSets.flatMap { evidence.attempts[$0.id] ?? [] }.sorted(by: LearningEvent.ordered)
        var successes: [LearningEvent] = []
        var completed: [LearningEvent] = []
        var contexts = Set<String>()
        for attempt in attempts {
            guard let context = attempt.contextID, UUID(uuidString: context) != nil,
                  let set = sets[attempt.targetID] else { continue }
            let selected = (evidence.answers[context] ?? []).filter { $0.timestamp <= attempt.timestamp }
            let complete = set.questions.allSatisfy { question in
                selected.filter { $0.targetID == question.id }.count == 1
            }
            // A placement flag alone is insufficient, including imported and legacy records.
            guard complete, contexts.insert(context).inserted else { continue }
            completed.append(attempt)
            let passed = !attempt.assisted && attempt.value == "passed" && set.questions.allSatisfy { question in
                selected.contains { $0.targetID == question.id && $0.value == String(question.answerIndex) &&
                    $0.correct == true && !$0.assisted }
            }
            if passed { successes.append(attempt) } else { successes.removeAll() }
        }
        let spaced = successes.contains { first in
            successes.contains { second in
                first.targetID != second.targetID && second.timestamp.timeIntervalSince(first.timestamp) >= 86_400
            }
        }
        let latestSuccess = successes.last?.timestamp
        var keys = Set<ReviewKey>()
        if spaced, let verifiedAt = latestSuccess {
            for id in rule.regularItemIDs {
                guard let item = pack.item(id) else { continue }
                for skill in item.skills {
                    let key = ReviewKey(itemID: id, skill: skill)
                    let latest = evidence.reviews[key]
                    let later = latest.flatMap { $0.timestamp >= verifiedAt ? $0 : nil }
                    if later.map({ !$0.assisted && ($0.rating ?? 0) >= 3 }) ?? true {
                        keys.insert(key)
                    }
                }
            }
        }
        let last = completed.last?.timestamp
        // Conservative product defaults, not a measured or personalized forgetting curve.
        let intervals: [TimeInterval] = [1, 1, 3, 7, 14, 30].map { $0 * 86_400 }
        var spacedSuccesses: [LearningEvent] = []
        for event in successes {
            if spacedSuccesses.last.map({ event.timestamp.timeIntervalSince($0.timestamp) >= 86_400 }) ?? true {
                spacedSuccesses.append(event)
            }
        }
        let interval = spaced ? intervals[min(spacedSuccesses.count, intervals.count - 1)] : 86_400
        let lastSeen = completed.reduce(into: [String: Date]()) { $0[$1.targetID] = $1.timestamp }
        let next = rule.practiceSets.min {
            let a = lastSeen[$0.id] ?? .distantPast, b = lastSeen[$1.id] ?? .distantPast
            return a == b ? $0.id < $1.id : a < b
        }!.id
        return Self(successfulSets: successes.count, verified: spaced, lastAttempt: last,
                    nextDue: last.map { $0.addingTimeInterval(interval) }, nextSetID: next,
                    consolidatedKeys: keys,
                    confirmedQuestionIDs: Set(successes.flatMap { sets[$0.targetID]?.questions.map(\.id) ?? [] }))
    }
}

public struct RuleKnowledge {
    public let consolidatedKeys: Set<ReviewKey>
    public let progress: [String: RuleProgress]
    private let directKnowledge: ReadingKnowledge

    public init(pack: ContentPack, events: [LearningEvent], now: Date = Date()) {
        let evidence = RuleEvidence(events: events, now: now)
        directKnowledge = evidence.directKnowledge
        progress = Dictionary(uniqueKeysWithValues: (pack.learningRules ?? []).map {
            ($0.id, RuleProgress.make($0, pack: pack, evidence: evidence))
        })
        consolidatedKeys = progress.values.reduce(into: Set<ReviewKey>()) { $0.formUnion($1.consolidatedKeys) }
    }

    public func ready(_ rule: LearningRule) -> Bool {
        if rule.prerequisiteIDs.isEmpty && rule.prerequisiteRuleIDs.isEmpty { return true }
        let wordsReady = !rule.prerequisiteIDs.isEmpty && rule.prerequisiteIDs.allSatisfy {
            directKnowledge.recalled($0, .reading) && directKnowledge.recalled($0, .meaning)
        }
        let rulesReady = !rule.prerequisiteRuleIDs.isEmpty && rule.prerequisiteRuleIDs.allSatisfy {
            (progress[$0]?.successfulSets ?? 0) > 0
        }
        return wordsReady || rulesReady
    }
}

extension ContentPack {
    public func rule(forSet id: String) -> LearningRule? {
        learningRules?.first { $0.practiceSets.contains { $0.id == id } }
    }
}
