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
    public var license: String?
    public var licenseURL: String?
    public var attribution: String?
}

public struct ContentCitation: Codable, Hashable {
    public let sourceID: String
    public let locator: String
    public let status: String
}

public struct KnowledgeItem: Codable, Identifiable {
    public let id: String
    public let kind: String
    public let level: String
    public let text: String
    public let reading: String
    public var acceptedReadings: [String]?
    public var readingCue: String?
    public let romaji: String
    public let meaning: String
    public let explanation: String
    public let sourceIDs: [String]
    public let status: String
    public var partOfSpeech: String?
    public var sense: String?
    public var register: String?
    public var tags: [String]?
    public var prerequisiteIDs: [String]?
    public var citations: [ContentCitation]?
    public var exampleSentenceIDs: [String]?
    public var order: Int?
    public var referenceExcerpt: String?
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
    public var citations: [ContentCitation]?
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
    public var skill: Skill?
    public var ability: String?
    public var evidence: String?
    public var citations: [ContentCitation]?
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
    public var prerequisiteIDs: [String]?
    public var objectives: [String]?
    public var diagnosticIDs: [String]?
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
    public let vocabulary: [ReadingWord]?
    public let grammarIDs: [String]?
    public var questions: [ReadingQuestion]?
    public var purpose: String?
    public var paragraphs: [ReadingParagraph]?
    public var citations: [ContentCitation]?

    public var allQuestions: [ReadingQuestion] {
        questions ?? [ReadingQuestion(id: id + "q1", prompt: question, choices: choices,
            answerIndex: answerIndex, explanation: explanation, evidenceSentenceIDs: sentenceIDs, ability: "information")]
    }
}

public struct ReadingQuestion: Codable, Identifiable {
    public let id: String
    public let prompt: String
    public let choices: [String]
    public let answerIndex: Int
    public let explanation: String
    public let evidenceSentenceIDs: [String]
    public let ability: String
}

public struct ReadingParagraph: Codable {
    public let sentenceIDs: [String]
    public let vocabulary: [ReadingWord]
}

public struct IntroModule: Codable, Identifiable {
    public let id: String
    public let title: String
    public let explanation: String
    public let examples: [String]
    public let questions: [ReadingQuestion]
    public let citations: [ContentCitation]
}

/// Author-checked content-word occurrences, including words outside the bundled dictionary.
/// Particles and inflection endings are assessed separately through grammar prerequisites.
public struct ReadingWord: Codable, Hashable {
    public let text: String
    public let itemID: String?
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
    public var introModules: [IntroModule]?
    private var itemIndex: [String: Int] = [:]
    private var sentenceIndex: [String: Int] = [:]
    private var exerciseIndex: [String: Int] = [:]
    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, version, title, notice, references, stages, items, sentences, exercises, lessons, readings, introModules
    }

    public static func bundled() throws -> ContentPack {
        guard let url = Bundle.module.url(forResource: "foundation", withExtension: "json") else {
            throw LearningError.invalid("找不到课程文件，请重新安装应用。")
        }
        var pack = try JSONDecoder().decode(ContentPack.self, from: Data(contentsOf: url))
        try pack.validate()
        pack.itemIndex = Dictionary(uniqueKeysWithValues: pack.items.enumerated().map { ($0.element.id, $0.offset) })
        pack.sentenceIndex = Dictionary(uniqueKeysWithValues: pack.sentences.enumerated().map { ($0.element.id, $0.offset) })
        pack.exerciseIndex = Dictionary(uniqueKeysWithValues: pack.exercises.enumerated().map { ($0.element.id, $0.offset) })
        return pack
    }

    public func item(_ id: String) -> KnowledgeItem? {
        if let index = itemIndex[id] { return items[index] }; return items.first { $0.id == id }
    }
    public func sentence(_ id: String) -> AnnotatedSentence? {
        if let index = sentenceIndex[id] { return sentences[index] }; return sentences.first { $0.id == id }
    }
    public func exercise(_ id: String) -> Exercise? {
        if let index = exerciseIndex[id] { return exercises[index] }; return exercises.first { $0.id == id }
    }

    public func validate() throws {
        guard [1, 2].contains(schemaVersion) else { throw LearningError.invalid("课程格式版本不受支持。") }
        func unique(_ ids: [String]) -> Bool { Set(ids).count == ids.count && ids.allSatisfy { !$0.isEmpty } }
        let groups = [items.map(\.id), sentences.map(\.id), exercises.map(\.id), lessons.map(\.id), readings.map(\.id)]
        guard groups.allSatisfy(unique) else { throw LearningError.invalid("课程包含重复或空编号。") }
        let itemIDs = Set(items.map(\.id)), sentenceIDs = Set(sentences.map(\.id))
        let knownItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let exerciseIDs = Set(exercises.map(\.id)), readingIDs = Set(readings.map(\.id))
        let sourceIDs = Set(references.map(\.id))
        guard items.allSatisfy({ ["word", "grammar"].contains($0.kind) && !$0.meaning.isEmpty &&
            !$0.sourceIDs.isEmpty && Set($0.sourceIDs).isSubset(of: sourceIDs) &&
            ($0.kind != "word" || !$0.reading.isEmpty) }) else {
            throw LearningError.invalid("词条内容或资料来源不完整。")
        }
        guard items.allSatisfy({ item in
            guard let alternatives = item.acceptedReadings else { return true }
            return item.kind == "word" && !alternatives.isEmpty &&
                unique(([item.reading] + alternatives).map { AnswerChecker.normalizeKana($0) })
        }) else { throw LearningError.invalid("同一义项的其他读音无效。") }
        guard sentences.allSatisfy({ !$0.text.isEmpty && !$0.translation.isEmpty && $0.segments.allSatisfy {
            !$0.text.isEmpty && ($0.itemID == nil || itemIDs.contains($0.itemID!))
        } }) else { throw LearningError.invalid("例句标注不完整。") }
        guard exercises.allSatisfy({ itemIDs.contains($0.targetID) && sentenceIDs.contains($0.sentenceID) &&
            (knownItems[$0.targetID]?.skills.contains($0.skill ?? .grammar) ?? false) &&
            $0.choices.count >= 2 && Set($0.choices).count == $0.choices.count &&
            $0.choices.indices.contains($0.answerIndex) && !$0.explanation.isEmpty }) else {
            throw LearningError.invalid("练习引用或答案无效。")
        }
        guard readings.allSatisfy({ !$0.sentenceIDs.isEmpty && Set($0.sentenceIDs).isSubset(of: sentenceIDs) &&
            $0.choices.indices.contains($0.answerIndex) &&
            ($0.vocabulary?.allSatisfy { word in
                !word.text.isEmpty && (word.itemID == nil || knownItems[word.itemID!]?.kind == "word")
            } ?? true) &&
            ($0.grammarIDs?.allSatisfy { knownItems[$0]?.kind == "grammar" } ?? true)
        }) else { throw LearningError.invalid("短文引用或答案无效。") }
        guard lessons.allSatisfy({ !($0.itemIDs.isEmpty || $0.sentenceIDs.isEmpty || $0.exerciseIDs.isEmpty) &&
            Set($0.itemIDs).isSubset(of: itemIDs) && Set($0.sentenceIDs).isSubset(of: sentenceIDs) &&
            Set($0.exerciseIDs).isSubset(of: exerciseIDs) && ($0.readingID == nil || readingIDs.contains($0.readingID!))
        }) else { throw LearningError.invalid("学习单元引用无效。") }
        guard items.allSatisfy({ ($0.exampleSentenceIDs.map { Set($0).isSubset(of: sentenceIDs) } ?? true) }) else {
            throw LearningError.invalid("词条例句引用缺失。")
        }
        let questions = readings.flatMap(\.allQuestions) + (introModules ?? []).flatMap(\.questions)
        guard unique(questions.map(\.id)), questions.allSatisfy({
            !$0.prompt.isEmpty && (2...4).contains($0.choices.count) && Set($0.choices).count == $0.choices.count &&
            $0.choices.indices.contains($0.answerIndex) && !$0.explanation.isEmpty &&
            Set($0.evidenceSentenceIDs).isSubset(of: sentenceIDs)
        }) else { throw LearningError.invalid("题组、答案或证据引用无效。") }
        guard readings.allSatisfy({ reading in
            [nil, "practice", "assessment", "extensive"].contains(reading.purpose) && (1...4).contains(reading.allQuestions.count) &&
            reading.allQuestions.allSatisfy { !$0.evidenceSentenceIDs.isEmpty && Set($0.evidenceSentenceIDs).isSubset(of: Set(reading.sentenceIDs)) } &&
            (reading.paragraphs == nil || reading.paragraphs!.flatMap(\.sentenceIDs) == reading.sentenceIDs) &&
            (reading.paragraphs == nil || reading.paragraphs!.flatMap(\.vocabulary) == reading.vocabulary)
        }) else { throw LearningError.invalid("阅读用途、段落或题目证据无效。") }
        func checkGraph(_ graph: [String: [String]]) throws {
            var visited = Set<String>(), active = Set<String>()
            func visit(_ id: String) throws {
                if active.contains(id) { throw LearningError.invalid("前置知识存在循环。") }
                if visited.contains(id) { return }
                active.insert(id)
                for next in graph[id] ?? [] {
                    guard graph[next] != nil else { throw LearningError.invalid("前置知识引用缺失。") }
                    try visit(next)
                }
                active.remove(id); visited.insert(id)
            }
            for id in graph.keys { try visit(id) }
        }
        try checkGraph(Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.prerequisiteIDs ?? []) }))
        try checkGraph(Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0.prerequisiteIDs ?? []) }))
        var citations: [ContentCitation] = []
        for item in items { citations.append(contentsOf: item.citations ?? []) }
        for sentence in sentences { citations.append(contentsOf: sentence.citations ?? []) }
        for reading in readings { citations.append(contentsOf: reading.citations ?? []) }
        for exercise in exercises { citations.append(contentsOf: exercise.citations ?? []) }
        for module in introModules ?? [] { citations.append(contentsOf: module.citations) }
        guard citations.allSatisfy({ sourceIDs.contains($0.sourceID) && !$0.locator.isEmpty &&
            ["reference", "adapted", "translated", "sourceChecked", "original"].contains($0.status) }) else {
            throw LearningError.invalid("内容来源或核验状态无效。")
        }
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
    public static func matches(_ answer: String, reading: String, alternatives: [String] = []) -> Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ([reading] + alternatives).contains { normalizeKana(answer) == normalizeKana($0) }
    }
}
