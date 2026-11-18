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
    public var jmdictEntryID: Int?
    public var pitchAccents: [WordPitchAccent]?
    /// Extra meanings keep their own review history. A different written form
    /// requires an explicitly checked dictionary identity and its own reading review.
    public var lexemeID: String?
    public var readingOwnerID: String?
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
    public var isLexeme: Bool { kind == "word" && lexemeID == nil }
    public var skills: [Skill] { kind == "word" ? (readingOwnerID == nil ? [.reading, .meaning] : [.meaning]) : [.grammar] }
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
    public var properNames: [String]? = nil

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
    public var allowsSyntheticSpeech: Bool?
}

/// Author-checked content-word occurrences, including words outside the bundled dictionary.
/// Particles and inflection endings are assessed separately through grammar prerequisites.
public struct ReadingWord: Codable, Hashable {
    public let text: String
    public let itemID: String?
    public var properName: Bool? = nil
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
    public var learningRules: [LearningRule]?
    private var itemIndex: [String: Int] = [:]
    private var sentenceIndex: [String: Int] = [:]
    private var exerciseIndex: [String: Int] = [:]
    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, version, title, notice, references, stages, items, sentences, exercises, lessons, readings, introModules, learningRules
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

    public var wordCount: Int { items.filter(\.isLexeme).count }
    public func hasSenseVariants(_ item: KnowledgeItem) -> Bool {
        item.kind == "word" && (item.lexemeID != nil || items.contains { $0.lexemeID == item.id })
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
        guard items.allSatisfy({ item in
            guard let id = item.lexemeID else { return true }
            guard let owner = knownItems[id] else { return false }
            let readings = Set(([item.reading] + (item.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
            let ownerReadings = Set(([owner.reading] + (owner.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
            return item.kind == "word" && owner.isLexeme && id != item.id &&
                (item.text == owner.text || (item.jmdictEntryID != nil && item.jmdictEntryID == owner.jmdictEntryID)) &&
                readings.isSubset(of: ownerReadings) && item.meaning != owner.meaning &&
                (item.prerequisiteIDs ?? []).contains(id)
        }) else { throw LearningError.invalid("词义与原词的关联无效。") }
        guard items.allSatisfy({ item in
            guard let id = item.readingOwnerID else { return true }
            guard let owner = knownItems[id], item.lexemeID == id else { return false }
            let readings = Set(([item.reading] + (item.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
            let ownerReadings = Set(([owner.reading] + (owner.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
            return item.text == owner.text && readings == ownerReadings
        }) else { throw LearningError.invalid("不同字形或读音条件不能共用认读练习。") }
        guard items.allSatisfy({ item in
            guard let entry = item.jmdictEntryID else { return true }
            return item.kind == "word" && entry > 0 && item.sourceIDs.contains("jmdict") &&
                (item.citations ?? []).contains { $0.sourceID == "jmdict" && $0.locator.hasPrefix("JMdict entry \(entry)；") }
        }) else { throw LearningError.invalid("词条的词典编号或出处无效。") }
        let dictionaryGroups = Dictionary(grouping: items.filter { $0.jmdictEntryID != nil }, by: { $0.jmdictEntryID! })
        guard dictionaryGroups.values.allSatisfy({ words in
            words.enumerated().allSatisfy { index, word in
                let readings = Set(([word.reading] + (word.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
                return words.dropFirst(index + 1).allSatisfy { other in
                    let others = Set(([other.reading] + (other.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
                    return readings.isDisjoint(with: others) || (word.lexemeID ?? word.id) == (other.lexemeID ?? other.id)
                }
            }
        }) else { throw LearningError.invalid("同一词条的同读音用法不能重复计为新词。") }
        let wordForms = Dictionary(grouping: items.filter { $0.kind == "word" }, by: \.text)
        guard wordForms.values.allSatisfy({ words in
            words.enumerated().allSatisfy { index, word in
                let readings = Set(([word.reading] + (word.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
                return words.dropFirst(index + 1).allSatisfy { other in
                    let others = Set(([other.reading] + (other.acceptedReadings ?? [])).map(AnswerChecker.normalizeKana))
                    return readings.isDisjoint(with: others) ||
                        ((word.lexemeID ?? word.id) == (other.lexemeID ?? other.id) && word.meaning != other.meaning)
                }
            }
        }) else { throw LearningError.invalid("同词的不同义项需要明确关联，不能重复计为新词。") }
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
        guard readings.allSatisfy({ reading in
            let names = reading.properNames ?? []
            guard unique(names) && names.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
            let words = reading.vocabulary ?? []
            let declared = Set(names)
            guard Set(words.filter { $0.properName == true }.map(\.text)) == declared else { return false }
            return words.allSatisfy { word in
                if word.properName == true { return word.itemID == nil && declared.contains(word.text) }
                return word.itemID != nil || !["N3", "N2"].contains(reading.level)
            }
        }) else { throw LearningError.invalid("专名声明无效，或阅读仍含未教学的内容词。") }
        guard lessons.allSatisfy({ !($0.itemIDs.isEmpty || $0.sentenceIDs.isEmpty || $0.exerciseIDs.isEmpty) &&
            Set($0.itemIDs).isSubset(of: itemIDs) && Set($0.sentenceIDs).isSubset(of: sentenceIDs) &&
            Set($0.exerciseIDs).isSubset(of: exerciseIDs) && ($0.readingID == nil || readingIDs.contains($0.readingID!))
        }) else { throw LearningError.invalid("学习单元引用无效。") }
        guard items.allSatisfy({ ($0.exampleSentenceIDs.map { Set($0).isSubset(of: sentenceIDs) } ?? true) }) else {
            throw LearningError.invalid("词条例句引用缺失。")
        }
        guard items.allSatisfy({ item in
            (item.pitchAccents ?? []).allSatisfy { accent in
                item.kind == "word" && accent.isValid &&
                ([item.reading] + (item.acceptedReadings ?? [])).contains(accent.reading)
            }
        }) else { throw LearningError.invalid("词语重音的拍数、读音或来源无效。") }
        let rules = learningRules ?? []
        let ruleIDs = Set(rules.map(\.id))
        guard unique(rules.map(\.id)), unique(rules.flatMap { $0.practiceSets.map(\.id) }),
              Set(rules.flatMap { $0.practiceSets.map(\.id) }).isDisjoint(with: ruleIDs),
              rules.allSatisfy({ rule in
                  !rule.title.isEmpty && !rule.explanation.isEmpty && !rule.examples.isEmpty && !rule.exceptions.isEmpty &&
                  !rule.citations.isEmpty && rule.practiceSets.count >= 3 &&
                  rule.practiceSets.allSatisfy { $0.questions.count == 4 } &&
                  unique(rule.regularItemIDs) && Set(rule.prerequisiteIDs).isSubset(of: itemIDs) &&
                  rule.prerequisiteIDs.allSatisfy { knownItems[$0]?.kind == "word" } &&
                  rule.regularItemIDs.allSatisfy { knownItems[$0]?.kind == "word" && knownItems[$0]?.lexemeID == nil } &&
                  Set(rule.prerequisiteRuleIDs).isSubset(of: ruleIDs)
              }), unique(rules.flatMap(\.regularItemIDs)) else {
            throw LearningError.invalid("规则的前置知识、常规词项或迁移题组无效。")
        }
        let questions = readings.flatMap(\.allQuestions) + (introModules ?? []).flatMap(\.questions) +
            rules.flatMap { $0.practiceSets.flatMap(\.questions) }
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
        try checkGraph(Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0.prerequisiteRuleIDs) }))
        var citations: [ContentCitation] = []
        for item in items {
            citations.append(contentsOf: item.citations ?? [])
            for accent in item.pitchAccents ?? [] { citations.append(contentsOf: accent.citations) }
        }
        for sentence in sentences { citations.append(contentsOf: sentence.citations ?? []) }
        for reading in readings { citations.append(contentsOf: reading.citations ?? []) }
        for exercise in exercises { citations.append(contentsOf: exercise.citations ?? []) }
        for module in introModules ?? [] { citations.append(contentsOf: module.citations) }
        for rule in rules { citations.append(contentsOf: rule.citations) }
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
        // ICU script transliteration expands ー using the preceding vowel.
        // Convert kana code points directly so explicit long-vowel spellings
        // remain distinct and are accepted only through authored alternatives.
        let scalars = narrow.precomposedStringWithCanonicalMapping.unicodeScalars.map { scalar -> UnicodeScalar in
            if (0x30A1...0x30F6).contains(scalar.value) {
                return UnicodeScalar(scalar.value - 0x60)!
            }
            return scalar
        }
        return String(String.UnicodeScalarView(scalars)).precomposedStringWithCanonicalMapping
            .filter { !$0.isWhitespace }
    }
    public static func matches(_ answer: String, reading: String, alternatives: [String] = []) -> Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ([reading] + alternatives).contains { normalizeKana(answer) == normalizeKana($0) }
    }
}
