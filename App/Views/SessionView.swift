import SwiftUI
import LearningCore

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: StudyClock
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyMinutes") private var minutes = 20
    private var studiedToday: TimeInterval { StudyTime.today(events: model.events, live: clock.pendingInterval) }
    private var goalReached: Bool { studiedToday >= Double(minutes * 60) }
    private var moreAvailable: Bool { ((try? model.plannedTasks(minutes: minutes).isEmpty) == false) }

    var body: some View {
        VStack(spacing: 0) {
            if let checkpoint = model.checkpoint, let entry = checkpoint.current {
                sessionHeader(checkpoint)
                ZStack {
                    taskView(entry).id(entry.id)
                        .opacity(clock.isManuallyPaused ? 0.12 : 1)
                        .allowsHitTesting(!clock.isManuallyPaused)
                        .accessibilityHidden(clock.isManuallyPaused)
                    if clock.isManuallyPaused { pausedView }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { completionView }
        }
        .background(Color(UIColor.systemBackground))
        .navigationTitle("学习").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { leave() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("保存并离开").accessibilityIdentifier("study.close")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("结束本次安排") { model.perform { try model.finishSession(); dismiss() } }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("学习选项")
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onAppear { model.perform { try model.updateStudyTiming() } }
        .onChange(of: model.checkpoint?.id) { _ in model.perform { try model.updateStudyTiming() } }
        .onChange(of: model.checkpoint?.current == nil) { _ in model.perform { try model.updateStudyTiming() } }
        .onDisappear {
            model.perform { try clock.setVisible(false) }
            model.speech.stop()
        }
    }

    private func sessionHeader(_ checkpoint: SessionCheckpoint) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text("\(checkpoint.index + 1) / \(checkpoint.entries.count)")
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Label(StudyTime.clock(clock.elapsedSeconds), systemImage: "timer")
                    .font(.subheadline.monospacedDigit())
                    .accessibilityLabel("本轮学习 \(StudyTime.clock(clock.elapsedSeconds))")
                    .accessibilityIdentifier("study.timer")
                Button {
                    model.perform {
                        if clock.isManuallyPaused { try clock.resume() }
                        else { try clock.pause(); model.speech.stop() }
                    }
                } label: { Image(systemName: clock.isManuallyPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(clock.isManuallyPaused ? "继续计时" : "暂停学习")
                    .accessibilityIdentifier("study.pause")
            }
            ProgressView(value: min(studiedToday, Double(minutes * 60)), total: Double(minutes * 60))
                .accessibilityLabel("今日学习时间进度")
            if goalReached {
                Text("今日时间目标已完成，可以继续学习或结束。").font(.caption).foregroundColor(.accentColor)
            }
        }.padding(.horizontal, 18).padding(.bottom, 8)
    }

    private var pausedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "pause.circle").font(.system(size: 40, weight: .light)).foregroundColor(.accentColor)
            Text("已暂停").font(.title2.weight(.semibold))
            Text("休息一下，学习进度已保存。").font(.subheadline).foregroundColor(.secondary)
            Button("继续学习") { model.perform { try clock.resume() } }
                .buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("study.resume")
        }.padding(28).frame(maxWidth: 340)
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 48, weight: .light)).foregroundColor(.accentColor)
            Text(goalReached ? "今日目标已完成" : "本轮练习完成").font(.title2.weight(.semibold))
            Text("本轮 \(StudyTime.clock(clock.elapsedSeconds)) · 今日 \(StudyTime.clock(studiedToday))")
                .font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
            Text(goalReached ? "按自己的节奏，继续阅读。" : (moreAvailable ? "距离今天的目标还需 \(StudyTime.clock(Double(minutes * 60) - studiedToday))。" : "今日可安排的内容已完成，无需重复凑满时间。"))
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
            if !goalReached && moreAvailable {
                Button("继续下一轮") {
                    model.perform { try model.finishSession(); try model.startToday(minutes: minutes) }
                }.buttonStyle(StudyPrimaryButtonStyle())
                    .accessibilityIdentifier("study.nextRound")
            }
            Button(goalReached ? "完成学习" : "先到这里") {
                model.perform { try model.finishSession(); dismiss() }
            }.buttonStyle(StudyQuietButtonStyle())
                .accessibilityIdentifier("study.finish")
        }.padding(24)
    }

    @ViewBuilder private func taskView(_ entry: SessionEntry) -> some View {
        let assisted = model.checkpoint?.assistedEntryIDs.contains(entry.id) ?? false
        switch entry.task {
        case .recall(let key):
            if let item = model.pack.item(key.itemID) {
                RecallCard(item: item, skill: key.skill, previouslyAssisted: assisted, onAssistance: { assist(entry) }) {
                    answer(entry, $0, $1)
                }
            } else { missing }
        case .exercise(let id):
            if let exercise = model.pack.exercise(id), let sentence = model.pack.sentence(exercise.sentenceID) {
                StructureCard(exercise: exercise, sentence: sentence, previouslyAssisted: assisted,
                              onAssistance: { assist(entry) }, onSelection: { record(entry, $0, $1) }) {
                    answer(entry, $0, $1)
                }
            } else { missing }
        case .reading(let id):
            if let reading = model.pack.readings.first(where: { $0.id == id }) {
                ReadingCard(reading: reading, entryID: entry.id, previouslyAssisted: assisted,
                            onAssistance: { assist(entry) })
            } else { missing }
        }
    }
    private func leave() {
        model.perform { try clock.setVisible(false); model.speech.stop(); dismiss() }
    }
    private func answer(_ entry: SessionEntry, _ rating: Int, _ assisted: Bool) {
        model.speech.stop()
        model.perform { try model.answer(entryID: entry.id, rating: rating, assisted: assisted) }
    }
    private func assist(_ entry: SessionEntry) { model.perform { try model.markAssisted(entryID: entry.id) } }
    private func record(_ entry: SessionEntry, _ rating: Int, _ assisted: Bool) {
        model.perform { try model.recordAnswer(entryID: entry.id, rating: rating, assisted: assisted) }
    }
    private var missing: some View {
        VStack(spacing: 16) {
            Text("这项内容暂时不可用，请更新课程。")
            Button("结束本次安排") { model.perform { try model.finishSession(); dismiss() } }
                .buttonStyle(StudyPrimaryButtonStyle())
        }.padding(24)
    }
}

private struct RecallCard: View {
    @EnvironmentObject private var model: AppModel
    let item: KnowledgeItem
    let skill: Skill
    let previouslyAssisted: Bool
    let onAssistance: () -> Void
    let onAnswer: (Int, Bool) -> Void
    @AppStorage("showRomaji") private var showRomaji = false
    @AppStorage("voiceID") private var voiceID = ""
    @State private var answer = ""
    @State private var revealed = false
    @State private var assisted = false
    @State private var typedCorrect: Bool?
    @FocusState private var typing: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var wordSize: CGFloat = 42
    private var needsAgain: Bool { assisted || previouslyAssisted || typedCorrect == false }
    private var hasLongExplanation: Bool { revealed && (item.explanation.count > 80 || item.meaning.count > 28) }

    var body: some View {
        StudyCardLayout(scrolling: hasLongExplanation) { compact in
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                HStack {
                    Text(skill.title).font(.caption.weight(.medium)).foregroundColor(.secondary)
                    Spacer()
                    Text(item.level).font(.caption).foregroundColor(.secondary)
                }
                Text(item.text).font(.system(size: compact ? wordSize * 0.81 : wordSize, weight: .medium))
                    .minimumScaleFactor(0.75).lineLimit(2)
                if skill == .reading && !revealed, let cue = item.readingCue {
                    Text(cue).font(.subheadline).foregroundColor(.secondary)
                }
                if skill == .meaning || revealed {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.reading).font(.title3).foregroundColor(.secondary)
                            if revealed, let alternatives = item.acceptedReadings, !alternatives.isEmpty {
                                Text("也读作：" + alternatives.joined(separator: "、")).font(.caption).foregroundColor(.secondary)
                            }
                            if revealed && showRomaji && !item.romaji.isEmpty { Text(item.romaji).font(.caption).foregroundColor(.secondary) }
                        }
                        Spacer()
                        if revealed { speechButton(slow: false); speechButton(slow: true) }
                    }
                }
                if revealed {
                    Divider().padding(.vertical, 2)
                    Text(item.meaning).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(item.explanation).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let correct = typedCorrect {
                        Label(correct ? "读音正确" : "再看一次，下次继续", systemImage: correct ? "checkmark.circle" : "arrow.counterclockwise")
                            .font(.caption).foregroundColor(.accentColor)
                    }
                } else {
                    Text(skill == .reading ? "这个词怎么读？" : "这个词是什么意思？").font(.headline)
                    if skill == .reading {
                        TextField("输入假名（可选）", text: $answer)
                            .padding(12).background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .textInputAutocapitalization(.never).disableAutocorrection(true)
                            .focused($typing).submitLabel(.done).onSubmit { reveal() }
                            .accessibilityIdentifier("study.kanaInput")
                    }
                    if !typing {
                        Button("需要一点提示") { onAssistance(); assisted = true; reveal(checkTyped: false) }
                            .buttonStyle(StudyQuietButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            }
        } actions: {
            if !revealed {
                Button(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "显示答案" : "检查答案") { reveal() }
                    .buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("study.reveal")
            } else if needsAgain {
                VStack(spacing: 8) {
                    Text("这项会安排再次练习").font(.caption).foregroundColor(.secondary)
                    Button("继续") { onAnswer(1, assisted || previouslyAssisted) }
                        .buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("study.continue")
                }
            } else {
                VStack(spacing: 8) {
                    Text("按刚才回想的表现选择").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        grade("忘记", 1); grade("费力", 2); grade("记得", 3); grade("熟悉", 4)
                    }
                }
            }
        }
    }
    private func reveal(checkTyped: Bool = true) {
        typing = false
        if checkTyped && skill == .reading && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            typedCorrect = AnswerChecker.matches(answer, reading: item.reading, alternatives: item.acceptedReadings ?? [])
            if typedCorrect == false { onAssistance() }
        }
        revealed = true
    }
    private func grade(_ label: String, _ rating: Int) -> some View {
        Button { onAnswer(rating, false) } label: {
            Text(label).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundColor(rating == 3 ? .accentColor : .primary)
                .background(rating == 3 ? Color.accentColor.opacity(0.11) : Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
            .buttonStyle(StudyPressFeedbackStyle()).accessibilityIdentifier("study.grade.\(rating)")
            .accessibilityLabel(rating == 2 ? "已经想起，但比较费力" : label)
    }
    private func speechButton(slow: Bool) -> some View {
        Button { model.perform { try model.speech.speak(item.reading, slow: slow, voiceID: voiceID) } } label: {
            Image(systemName: slow ? "tortoise" : "speaker.wave.2")
        }.buttonStyle(StudyIconButtonStyle()).accessibilityLabel(slow ? "慢速朗读" : "朗读")
    }
}

private struct StructureCard: View {
    @EnvironmentObject private var model: AppModel
    let exercise: Exercise
    let sentence: AnnotatedSentence
    let previouslyAssisted: Bool
    let onAssistance: () -> Void
    let onSelection: (Int, Bool) -> Void
    let onAnswer: (Int, Bool) -> Void
    @State private var assisted = false
    @State private var showHint = false
    @State private var selected: KnowledgeItem?
    @State private var choice: Int?
    private var usedHelp: Bool { assisted || previouslyAssisted }

    var body: some View {
        // Examples can also overflow at large text sizes before a hint is opened.
        // Short examples fit without a gesture; only the upper area can scroll.
        StudyCardLayout(scrolling: true) { compact in
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                Text(exercise.transfer ? "换个句子试试" : "读懂句子").font(.caption.weight(.medium)).foregroundColor(.secondary)
                RubyText(segments: sentence.segments) { lookup($0) }
                Text(exercise.prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
                HStack {
                    LookupMenu(sentenceIDs: [sentence.id]) { lookup($0) }
                    Spacer()
                    if choice == nil {
                        Button("提示") { onAssistance(); showHint = true; assisted = true }
                            .buttonStyle(StudyQuietButtonStyle())
                            .accessibilityIdentifier("study.hintButton")
                    }
                }
                if showHint && choice == nil {
                    Text(exercise.hint).font(.callout).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("study.hint")
                }
                if let choice = choice {
                    AnswerFeedback(correct: choice == exercise.answerIndex,
                                   answer: exercise.choices[exercise.answerIndex],
                                   explanation: sentence.translation + "\n" + exercise.explanation)
                }
                Spacer(minLength: 0)
            }
        } actions: {
            if let choice = choice {
                Button("继续") { onAnswer(choice == exercise.answerIndex && !usedHelp ? 3 : 1, usedHelp) }
                    .buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("study.continue")
            } else {
                ChoiceAnswers(choices: exercise.choices) { index in
                    choice = index
                    onSelection(index == exercise.answerIndex && !usedHelp ? 3 : 1, usedHelp)
                }
            }
        }
        .sheet(item: $selected) { item in NavigationView { ItemDetailView(item: item) }.navigationViewStyle(.stack) }
    }
    private func lookup(_ id: String) {
        if choice == nil { onAssistance(); assisted = true }
        selected = model.pack.item(id)
    }
}

private struct ReadingCard: View {
    @EnvironmentObject private var model: AppModel
    let reading: ReadingPassage
    let entryID: UUID
    let previouslyAssisted: Bool
    let onAssistance: () -> Void
    @State private var assisted = false
    @State private var showReading = false
    @State private var selected: KnowledgeItem?
    @State private var choice: Int?
    private var usedHelp: Bool { assisted || previouslyAssisted }
    private var index: Int { model.checkpoint?.questionIndex ?? 0 }
    private var question: ReadingQuestion { reading.allQuestions[min(index, reading.allQuestions.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(reading.title).font(.headline)
                Spacer()
                Button(showReading ? "收起注音" : "注音") {
                    showReading.toggle()
                    if showReading && choice == nil { onAssistance(); assisted = true }
                }.buttonStyle(StudyQuietButtonStyle())
                LookupMenu(sentenceIDs: reading.sentenceIDs) { lookup($0) }
            }.padding(.horizontal, 18).padding(.bottom, 8)
            let readiness = ReadingReadiness.assess(reading, pack: model.pack, knowledge: model.readingKnowledge)
            Text("已会实词 \(readiness.percentage)% · 待学 \(readiness.unfamiliarWords.count) 词")
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 4)
                .accessibilityIdentifier("study.readingCoverage")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(reading.sentenceIDs.compactMap { model.pack.sentence($0) }) { sentence in
                        RubyText(segments: sentence.segments, showReading: showReading) { lookup($0) }
                            .background(choice != nil && reading.questions != nil && question.evidenceSentenceIDs.contains(sentence.id)
                                ? Color.accentColor.opacity(0.08) : Color.clear)
                    }
                }.padding(.horizontal, 18).padding(.vertical, 8)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("study.readingScroll")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.55)
                VStack(alignment: .leading, spacing: 12) {
                    if reading.allQuestions.count > 1 {
                        Text("理解 \(index + 1) / \(reading.allQuestions.count)").font(.caption).foregroundColor(.secondary)
                    }
                    Text(question.prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let choice = choice {
                        AnswerFeedback(correct: choice == question.answerIndex,
                                       answer: question.choices[question.answerIndex], explanation: question.explanation)
                        Button("继续") { model.perform { try model.advanceReadingQuestion(entryID: entryID, questionID: question.id) } }
                            .buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("study.continue")
                    } else {
                        ChoiceAnswers(choices: question.choices) { selection in
                            model.perform { try model.recordReadingSelection(entryID: entryID, questionID: question.id, selection: selection, assisted: usedHelp) }
                            if model.errorMessage == nil { choice = selection }
                        }
                    }
                }.padding(.horizontal, 18).padding(.vertical, 12)
            }.background(Color(UIColor.systemBackground))
        }
        .sheet(item: $selected) { item in NavigationView { ItemDetailView(item: item) }.navigationViewStyle(.stack) }
        .onChange(of: index) { _ in choice = nil }
    }
    private func lookup(_ id: String) {
        if choice == nil { onAssistance(); assisted = true }
        selected = model.pack.item(id)
    }
}

private struct LookupMenu: View {
    @EnvironmentObject private var model: AppModel
    let sentenceIDs: [String]
    let onLookup: (String) -> Void
    private var ids: [String] {
        Array(Set(sentenceIDs.compactMap { model.pack.sentence($0) }.flatMap { $0.segments.compactMap(\.itemID) })).sorted()
    }
    var body: some View {
        Menu {
            ForEach(ids, id: \.self) { id in
                if let item = model.pack.item(id) { Button(item.text) { onLookup(id) } }
            }
        } label: { Label("词语", systemImage: "text.book.closed") }
            .buttonStyle(StudyQuietButtonStyle()).accessibilityLabel("查看词语")
    }
}

struct ChoiceAnswers: View {
    let choices: [String]
    let onSelect: (Int) -> Void
    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices.indices, id: \.self) { index in
                Button { onSelect(index) } label: {
                    HStack(spacing: 12) {
                        Text(String(UnicodeScalar(65 + index)!)).font(.caption.weight(.medium))
                            .foregroundColor(.secondary).frame(width: 23, height: 23)
                            .background(Color(UIColor.systemBackground)).clipShape(Circle())
                        Text(choices[index]).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(StudyPressFeedbackStyle()).accessibilityIdentifier("study.choice.\(index)")
            }
        }
    }
}

struct AnswerFeedback: View {
    let correct: Bool
    let answer: String
    let explanation: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(correct ? "理解正确" : "一起看一下", systemImage: correct ? "checkmark.circle.fill" : "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold)).foregroundColor(.accentColor)
            if !correct { Text("正确答案：\(answer)").font(.subheadline.weight(.medium)) }
            Text(explanation).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
