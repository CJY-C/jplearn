import SwiftUI
import LearningCore

struct RuleExplanation: View {
    let rule: LearningRule
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(rule.explanation).font(.callout)
            ForEach(rule.examples, id: \.self) { Text($0).font(.headline) }
            Text("边界与例外").font(.subheadline.weight(.semibold))
            ForEach(rule.exceptions, id: \.self) { Text($0).font(.callout).foregroundColor(.secondary) }
        }
    }
}

struct RuleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let rule: LearningRule
    @State private var session = false
    var body: some View {
        let knowledge = RuleKnowledge(pack: model.pack, events: model.events)
        return StudyCardLayout(scrolling: true) { _ in
            VStack(alignment: .leading, spacing: 16) {
                Text("已经熟悉这类表达，可以直接验证；需要讲解时，先学规则与例外。")
                    .font(.callout)
                Text("每组 \(rule.practiceSets.first?.questions.count ?? 0) 题 · 换实例运用")
                    .font(.subheadline).foregroundColor(.secondary)
                Text(knowledge.progress[rule.id]?.title ?? "待学习与验证").font(.subheadline.weight(.medium))
                Text(rule.regularItemIDs.isEmpty
                    ? "换例子并隔天复测，检验能否迁移规则。原词的词义、读音和用法仍单独练习；会变形不会批量增加掌握词数。"
                    : "不同题组隔天通过后，常规组合改为整组复习。查看提示或答错后，需要再次验证；不会批量添加词汇掌握记录。")
                    .font(.caption).foregroundColor(.secondary)
                if !knowledge.ready(rule) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("自动安排前需完成基础；已有相关知识可直接验证。")
                        if !rule.prerequisiteIDs.isEmpty {
                            Text("基础词的读音与含义：" + rule.prerequisiteIDs.compactMap { model.pack.item($0)?.text }.joined(separator: "、"))
                        }
                        if !rule.prerequisiteRuleIDs.isEmpty {
                            Text((rule.prerequisiteIDs.isEmpty ? "先完成：" : "或先完成：") + rule.prerequisiteRuleIDs.compactMap { id in
                                model.pack.learningRules?.first { $0.id == id }?.title
                            }.joined(separator: "、"))
                        }
                    }.font(.callout).foregroundColor(.secondary)
                }
            }
        } actions: {
            VStack(spacing: 8) {
                Button("直接验证") { open(.verify) }
                    .buttonStyle(StudyPrimaryButtonStyle())
                    .accessibilityIdentifier("rule.start")
                Button("先学规则") { open(.learn) }
                    .buttonStyle(StudyQuietButtonStyle())
                    .accessibilityIdentifier("rule.learn")
            }.disabled(model.checkpoint != nil)
        }
        .navigationTitle(rule.topicTitle).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $session) { NavigationView { SessionView() }.navigationViewStyle(.stack) }
    }

    private func open(_ mode: RuleStudyMode) {
        model.perform { try model.startRule(rule, mode: mode); session = model.checkpoint != nil }
    }
}

struct RulePracticeCard: View {
    @EnvironmentObject private var model: AppModel
    let rule: LearningRule
    let practiceSet: RulePracticeSet
    let entryID: UUID
    @State private var started = false
    @State private var showRule = false
    private var index: Int { min(model.checkpoint?.questionIndex ?? 0, practiceSet.questions.count - 1) }
    private var question: ReadingQuestion { practiceSet.questions[index] }
    private var selection: Int? {
        model.events.first { $0.kind == .questionAttempt && $0.contextID == entryID.uuidString && $0.targetID == question.id }
            .flatMap { Int($0.value ?? "") }
    }
    var body: some View {
        StudyCardLayout(scrolling: true) { _ in
            VStack(alignment: .leading, spacing: 14) {
                Text(rule.topicTitle).font(.headline)
                if !started {
                    if showRule {
                        RuleExplanation(rule: rule)
                        Text("本轮包含讲解，记为有提示的学习练习；之后再独立复测。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    else {
                        Text("先用一组题看看能否举一反三。已经会的内容可以直接验证，需要时再看规则。")
                            .font(.callout)
                        Text("\(practiceSet.questions.count) 道题 · 不同实例与使用边界")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
                else {
                    Text("\(isAssisted ? "学习练习" : "规则迁移") · \(index + 1) / \(practiceSet.questions.count)")
                        .font(.caption).foregroundColor(.secondary)
                    Text(question.prompt).font(.title3.weight(.medium))
                    if let selection = selection {
                        AnswerFeedback(correct: selection == question.answerIndex,
                            answer: question.choices[question.answerIndex], explanation: question.explanation)
                    }
                    if showRule { RuleExplanation(rule: rule) }
                }
            }
        } actions: {
            if !started {
                VStack(spacing: 8) {
                    Button(showRule ? "开始练习" : "直接验证") { select(.verify) }
                        .buttonStyle(StudyPrimaryButtonStyle())
                        .accessibilityIdentifier("rule.practice")
                    if !showRule {
                        Button("先学规则") { select(.learn) }
                            .buttonStyle(StudyQuietButtonStyle())
                            .accessibilityIdentifier("rule.learn")
                    }
                }
            } else if selection == nil {
                VStack(spacing: 8) {
                    ChoiceAnswers(choices: question.choices) { selected in
                        model.perform { try model.recordRuleSelection(entryID: entryID, questionID: question.id, selection: selected) }
                    }
                    Button("查看规则") {
                        model.perform { try model.markAssisted(entryID: entryID); showRule = true }
                    }.buttonStyle(StudyQuietButtonStyle()).accessibilityIdentifier("rule.hint")
                }
            } else {
                Button("继续") {
                    model.perform { try model.advanceRuleQuestion(entryID: entryID, questionID: question.id); showRule = false }
                }.buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("study.continue")
            }
        }
        .onAppear {
            let setIDs = Set(rule.practiceSets.map(\.id))
            let mode = model.checkpoint?.ruleStudyMode(for: entryID)
            started = mode == .verify || model.events.contains {
                ($0.kind == .questionAttempt && $0.contextID == entryID.uuidString) ||
                (mode == nil && $0.kind == .placement && setIDs.contains($0.targetID))
            }
            showRule = !started && mode == .learn
        }
    }

    private var isAssisted: Bool { model.checkpoint?.assistedEntryIDs.contains(entryID) ?? false }

    private func select(_ mode: RuleStudyMode) {
        model.perform {
            try model.selectRuleStudyMode(mode, entryID: entryID)
            started = mode == .verify
            showRule = mode == .learn
        }
    }
}
