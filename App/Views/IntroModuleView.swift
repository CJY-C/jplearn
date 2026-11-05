import SwiftUI
import LearningCore

struct IntroModuleView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sessionID = UUID()
    @State private var index = 0
    @State private var selection: Int?
    @State private var correctCount = 0
    @State private var started = false
    @State private var finished = false
    let module: IntroModule

    var body: some View {
        StudyCardLayout { compact in
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                if finished {
                    Text(correctCount * 5 >= module.questions.count * 4 ? "这一项可以跳过" : "建议再看一下讲解")
                        .font(.title3.weight(.semibold))
                    Text("答对 \(correctCount) / \(module.questions.count)").font(.headline)
                    Text("诊断结果单独保存，不会生成词汇或句型的复习记录。")
                        .font(.callout).foregroundColor(.secondary)
                } else if started {
                    Text("诊断 \(index + 1) / \(module.questions.count)").font(.caption).foregroundColor(.secondary)
                    Text(module.questions[index].prompt).font(.title3.weight(.medium))
                    if let selection = selection {
                        let question = module.questions[index]
                        AnswerFeedback(correct: selection == question.answerIndex,
                                       answer: question.choices[question.answerIndex], explanation: question.explanation)
                    }
                } else {
                    Text(module.explanation).font(.callout)
                    ForEach(module.examples, id: \.self) { example in
                        HStack {
                            Text(example).font(.title3)
                            Spacer()
                            Button { model.perform { try model.speech.speak(example) } } label: { Image(systemName: "speaker.wave.2") }
                                .buttonStyle(StudyIconButtonStyle()).accessibilityLabel("朗读 \(example)")
                        }
                    }
                    Text("已经熟悉的话，可以直接做下方诊断。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
        } actions: {
            if finished {
                Button("重新检查") { index = 0; correctCount = 0; selection = nil; started = true; finished = false; startClock() }
                    .buttonStyle(StudyQuietButtonStyle())
            } else if !started {
                Button("开始诊断") { started = true }.buttonStyle(StudyPrimaryButtonStyle())
                    .accessibilityIdentifier("intro.start")
            } else if selection == nil {
                ChoiceAnswers(choices: module.questions[index].choices) { selection = $0 }
            } else {
                Button("继续") { advance() }.buttonStyle(StudyPrimaryButtonStyle())
                    .accessibilityIdentifier("study.continue")
            }
        }
        .navigationTitle(module.title).navigationBarTitleDisplayMode(.inline)
        .onAppear { startClock() }
        .onDisappear { model.perform { try model.studyClock.setVisible(false) }; model.speech.stop() }
    }

    private func startClock() {
        model.perform {
            try model.studyClock.bind(sessionID: sessionID, recordedSeconds: StudyTime.seconds(events: model.events, sessionID: sessionID))
            try model.studyClock.setVisible(true)
        }
    }
    private func advance() {
        guard let selected = selection else { return }
        let score = correctCount + (selected == module.questions[index].answerIndex ? 1 : 0)
        if index + 1 < module.questions.count { correctCount = score; index += 1; selection = nil }
        else {
            model.perform {
                try model.recordPlacement(moduleID: module.id, passed: score * 5 >= module.questions.count * 4)
                try model.studyClock.setVisible(false)
                correctCount = score; finished = true
            }
        }
    }
}

struct AssessmentListView: View {
    @EnvironmentObject private var model: AppModel
    let level: String
    @State private var session = false
    private var readings: [ReadingPassage] { model.pack.readings.filter { $0.level == level && $0.purpose == "assessment" } }
    var body: some View {
        List {
            if readings.isEmpty { Text("本阶段检测材料尚在制作。") }
            ForEach(readings) { reading in
                let attempted = model.events.contains { $0.kind == .readingAttempt && $0.targetID == reading.id }
                Button {
                    model.perform { try model.startAssessment(reading); session = model.checkpoint != nil }
                } label: {
                    HStack {
                        Text(attempted ? reading.title + " · 已检测" : "阅读检测 " + String((readings.firstIndex(where: { $0.id == reading.id }) ?? 0) + 1))
                        Spacer()
                        Image(systemName: attempted ? "checkmark.circle" : "arrow.right")
                    }
                }.disabled(attempted || model.checkpoint != nil)
            }
        }.navigationTitle(level + " 阅读检测").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $session) { NavigationView { SessionView() }.navigationViewStyle(.stack) }
    }
}
