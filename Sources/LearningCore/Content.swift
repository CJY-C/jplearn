import Foundation

public enum Skill: String, Codable, CaseIterable, Identifiable, Hashable {
    case meaning, reading, grammar
    public var id: String { rawValue }
    public var title: String {
        switch self { case .meaning: return "词义"; case .reading: return "读音"; case .grammar: return "表达理解" }
    }
}

public struct Reference: Codable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
}

public struct KnowledgeItem: Codable, Identifiable {
    public let id: String
    public let kind: String
    public let level: String
    public let text: String
    public let reading: String
    public let romaji: String
    public let meaning: String
    public let explanation: String
    public let sourceIDs: [String]
    public let status: String
    public var skills: [Skill] { kind == "word" ? [.reading, .meaning] : [.grammar] }
}

public struct RubySegment: Codable, Hashable {
    public let text: String
    public let reading: String?
    public let itemID: String?
}

public struct AnnotatedSentence: Codable, Identifiable {
    public let id: String
    public let segments: [RubySegment]
    public let translation: String
    public let explanation: String
    public let speechText: String?
    public var text: String { segments.map(\.text).joined() }
}

public struct Exercise: Codable, Identifiable {
    public let id: String
    public let targetID: String
    public let sentenceID: String
    public let prompt: String
    public let choices: [String]
    public let answerIndex: Int
    public let explanation: String
    public let hint: String
    public let transfer: Bool
}

public struct Lesson: Codable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let level: String
    public let itemIDs: [String]
    public let sentenceIDs: [String]
    public let exerciseIDs: [String]
    public let readingID: String?
}

public struct ReadingPassage: Codable, Identifiable {
    public let id: String
    public let title: String
    public let genre: String
    public let level: String
    public let sentenceIDs: [String]
    public let question: String
    public let choices: [String]
    public let answerIndex: Int
    public let explanation: String
}

public struct CurriculumStage: Codable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let vocabularyTarget: Int
    public let grammarTarget: Int
    public let readingTarget: Int
}

public enum LearningError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public struct ContentPack: Codable {
    public let schemaVersion: Int
    public let id: String
    public let version: String
    public let title: String
    public let notice: String
    public let references: [Reference]
    public let stages: [CurriculumStage]
    public let items: [KnowledgeItem]
    public let sentences: [AnnotatedSentence]
    public let exercises: [Exercise]
    public let lessons: [Lesson]
    public let readings: [ReadingPassage]

    public static func bundled() throws -> ContentPack {
        guard let url = Bundle.module.url(forResource: "foundation", withExtension: "json") else {
            throw LearningError.invalid("找不到课程文件，请重新安装应用。")
        }
        let pack = try JSONDecoder().decode(ContentPack.self, from: Data(contentsOf: url))
        try pack.validate()
        return pack
    }

    public func item(_ id: String) -> KnowledgeItem? { items.first { $0.id == id } }
    public func sentence(_ id: String) -> AnnotatedSentence? { sentences.first { $0.id == id } }
    public func exercise(_ id: String) -> Exercise? { exercises.first { $0.id == id } }

    public func validate() throws {
        guard schemaVersion == 1 else { throw LearningError.invalid("课程格式版本不受支持。") }
        func unique(_ ids: [String]) -> Bool { Set(ids).count == ids.count && ids.allSatisfy { !$0.isEmpty } }
        let groups = [items.map(\.id), sentences.map(\.id), exercises.map(\.id), lessons.map(\.id), readings.map(\.id)]
        guard groups.allSatisfy(unique) else { throw LearningError.invalid("课程包含重复或空编号。") }
        let itemIDs = Set(items.map(\.id)), sentenceIDs = Set(sentences.map(\.id))
        let exerciseIDs = Set(exercises.map(\.id)), readingIDs = Set(readings.map(\.id))
        let sourceIDs = Set(references.map(\.id))
        guard items.allSatisfy({ ["word", "grammar"].contains($0.kind) && !$0.meaning.isEmpty &&
            !$0.sourceIDs.isEmpty && Set($0.sourceIDs).isSubset(of: sourceIDs) &&
            ($0.kind != "word" || !$0.reading.isEmpty) }) else {
            throw LearningError.invalid("词条内容或资料来源不完整。")
        }
        guard sentences.allSatisfy({ !$0.text.isEmpty && !$0.translation.isEmpty && $0.segments.allSatisfy {
            !$0.text.isEmpty && ($0.itemID == nil || itemIDs.contains($0.itemID!))
        } }) else { throw LearningError.invalid("例句标注不完整。") }
        guard exercises.allSatisfy({ itemIDs.contains($0.targetID) && sentenceIDs.contains($0.sentenceID) &&
            $0.choices.count >= 2 && Set($0.choices).count == $0.choices.count &&
            $0.choices.indices.contains($0.answerIndex) && !$0.explanation.isEmpty }) else {
            throw LearningError.invalid("练习引用或答案无效。")
        }
        guard readings.allSatisfy({ !$0.sentenceIDs.isEmpty && Set($0.sentenceIDs).isSubset(of: sentenceIDs) &&
            $0.choices.indices.contains($0.answerIndex) }) else { throw LearningError.invalid("短文引用或答案无效。") }
        guard lessons.allSatisfy({ !($0.itemIDs.isEmpty || $0.sentenceIDs.isEmpty || $0.exerciseIDs.isEmpty) &&
            Set($0.itemIDs).isSubset(of: itemIDs) && Set($0.sentenceIDs).isSubset(of: sentenceIDs) &&
            Set($0.exerciseIDs).isSubset(of: exerciseIDs) && ($0.readingID == nil || readingIDs.contains($0.readingID!))
        }) else { throw LearningError.invalid("学习单元引用无效。") }
    }
}

public enum AnswerChecker {
    /// Normalize width and kana script, without equating distinct sounds such as おう / おお / おー.
    public static func normalizeKana(_ text: String) -> String {
        let narrow = text.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? text
        let hiragana = narrow.applyingTransform(.hiraganaToKatakana, reverse: true) ?? narrow
        return hiragana.precomposedStringWithCanonicalMapping
            .filter { !$0.isWhitespace }
    }
    public static func matches(_ answer: String, reading: String) -> Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizeKana(answer) == normalizeKana(reading)
    }
}
