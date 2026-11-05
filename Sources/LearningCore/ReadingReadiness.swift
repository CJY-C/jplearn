import Foundation

public struct ReadingKnowledge {
    private var latest: [ReviewKey: LearningEvent] = [:]
    public init(events: [LearningEvent]) {
        for event in events where event.kind == .review {
            guard let skill = event.skill else { continue }
            let key = ReviewKey(itemID: event.targetID, skill: skill)
            if latest[key].map({ LearningEvent.ordered($0, event) }) ?? true { latest[key] = event }
        }
    }
    func recalled(_ id: String, _ skill: Skill) -> Bool {
        guard let event = latest[ReviewKey(itemID: id, skill: skill)] else { return false }
        return !event.assisted && (event.rating ?? 0) >= 3
    }
}

public struct ReadingReadiness {
    public let knownOccurrences: Int
    public let totalOccurrences: Int
    public let unfamiliarWords: [ReadingWord]
    public let missingGrammarIDs: [String]
    public let isLong: Bool
    public var maximumParagraphUnknown: Int = 0
    public var extensive: Bool = false

    public var coverage: Double {
        totalOccurrences > 0 ? Double(knownOccurrences) / Double(totalOccurrences) : 0
    }
    public var percentage: Int { Int((coverage * 100).rounded(.down)) }
    public var isEligible: Bool {
        totalOccurrences > 0 && missingGrammarIDs.isEmpty &&
        coverage >= (extensive ? 0.98 : (isLong ? 0.95 : 0.80)) &&
        (isLong ? maximumParagraphUnknown <= 3 : unfamiliarWords.count <= 2)
    }

    public static func assess(_ reading: ReadingPassage, pack: ContentPack,
                              events: [LearningEvent]) -> ReadingReadiness {
        assess(reading, pack: pack, knowledge: ReadingKnowledge(events: events))
    }

    public static func assess(_ reading: ReadingPassage, pack: ContentPack,
                              knowledge: ReadingKnowledge) -> ReadingReadiness {
        let words = reading.vocabulary ?? []
        let unknown = words.filter { word in
            guard let id = word.itemID else { return true }
            return !knowledge.recalled(id, .meaning)
        }
        var seen = Set<String>()
        let distinct = unknown.filter { seen.insert($0.itemID ?? "outside:" + $0.text).inserted }
        let length = reading.sentenceIDs.compactMap { pack.sentence($0) }.reduce(0) { $0 + $1.text.count }
        let paragraphs = reading.paragraphs?.map(\.vocabulary) ?? [words]
        let maximumUnknown = paragraphs.map { paragraph in
            Set(paragraph.filter { $0.itemID.map { !knowledge.recalled($0, .meaning) } ?? true }
                .map { $0.itemID ?? "outside:" + $0.text }).count
        }.max() ?? 0
        return ReadingReadiness(knownOccurrences: words.count - unknown.count, totalOccurrences: words.count,
                                unfamiliarWords: distinct,
                                missingGrammarIDs: (reading.grammarIDs ?? []).filter { !knowledge.recalled($0, .grammar) },
                                isLong: length >= 150 || words.count >= 40,
                                maximumParagraphUnknown: maximumUnknown, extensive: reading.purpose == "extensive")
    }
}
