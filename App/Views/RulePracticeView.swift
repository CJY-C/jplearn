import SwiftUI
import LearningCore

struct RuleExplanation: View {
    let rule: LearningRule
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(rule.explanation).font(.callout)
            ForEach(rule.examples, id: \.self) { Text($0).font(.headline) }
            Text("边界与特殊读法").font(.subheadline.weight(.semibold))
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
                RuleExplanation(rule: rule)
                Text(knowledge.progress[rule.id]?.title ?? "待学习与验证").font(.subheadline.weight(.medium))
                Text("不同题组隔天通过后，常规组合改为整组复习。查看提示或答错后，需要再次验证；不会批量添加词汇掌握记录。")
                    .font(.caption).foregroundColor(.secondary)
                if !knowledge.ready(rule) {
                    Text("先完成数字规则的练习，或掌握一到十的读音与含义。").font(.callout).foregroundColor(.secondary)
                }
            }
        } actions: {
            Button("换例子练习") {
                model.perform { try model.startRule(rule); session = model.checkpoint != nil }
            }.buttonStyle(StudyPrimaryButtonStyle())
                .disabled(model.checkpoint != nil || !knowledge.ready(rule))
                .accessibilityIdentifier("rule.start")
        }
        .navigationTitle(rule.title).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $session) { NavigationView { SessionView() }.navigationViewStyle(.stack) }
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
                Text(rule.title).font(.headline)
                if !started { RuleExplanation(rule: rule) }
                else {
                    Text("规则迁移 · \(index + 1) / \(practiceSet.questions.count)").font(.caption).foregroundColor(.secondary)
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
                Button("换例子练习") { started = true }.buttonStyle(StudyPrimaryButtonStyle())
                    .accessibilityIdentifier("rule.practice")
            } else if selection == nil {
                VStack(spacing: 8) {
                    ChoiceAnswers(choices: question.choices) { selected in
                        model.perform { try model.recordRuleSelection(entryID: entryID, questionID: question.id, selection: selected) }
                    }
                    Button("查看规则") {
                        model.perform { try model.markAssisted(entryID: entryID); showRule = true }
                    }.buttonStyle(StudyQuietButtonStyle())
                }
            } else {
                Button("继续") {
                    model.perform { try model.advanceRuleQuestion(entryID: entryID, questionID: question.id); showRule = false }
                }.buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("study.continue")
            }
        }
        .onAppear {
            let setIDs = Set(rule.practiceSets.map(\.id))
            started = model.events.contains {
                ($0.kind == .questionAttempt && $0.contextID == entryID.uuidString) ||
                ($0.kind == .placement && setIDs.contains($0.targetID))
            }
        }
    }
}
