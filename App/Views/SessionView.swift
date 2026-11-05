import SwiftUI
import LearningCore

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let checkpoint = model.checkpoint, let entry = checkpoint.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ProgressView(value: Double(checkpoint.index), total: Double(max(1, checkpoint.entries.count)))
                        Text("\(checkpoint.index + 1) / \(checkpoint.entries.count)").font(.caption).foregroundColor(.secondary)
                        if checkpoint.assistedEntryIDs.contains(entry.id) {
                            Text("本题先前已使用提示，将安排再次练习。").font(.caption).foregroundColor(.secondary)
                        }
                        taskView(entry).id(entry.id)
                    }.padding(24)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal").font(.system(size: 54)).foregroundColor(.accentColor)
                    Text("这次就到这里").font(.title.bold())
                    Text("已完成的练习已经保存。\n留一点时间，慢慢读下去。")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                    Button("完成") {
                        model.perform { try model.finishSession(); dismiss() }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(24)
            }
        }
        .navigationTitle("学习").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { Button("稍后继续") { model.speech.stop(); dismiss() } }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("结束本次安排", role: .destructive) { model.perform { try model.finishSession(); dismiss() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onDisappear { model.speech.stop() }
    }

    @ViewBuilder private func taskView(_ entry: SessionEntry) -> some View {
        switch entry.task {
        case .recall(let key):
            if let item = model.pack.item(key.itemID) {
                RecallCard(item: item, skill: key.skill, onAssistance: { assist(entry) }) { rating, assisted in answer(entry, rating, assisted) }
            } else { missing(entry) }
        case .exercise(let id):
            if let exercise = model.pack.exercise(id), let sentence = model.pack.sentence(exercise.sentenceID) {
                StructureCard(exercise: exercise, sentence: sentence, onAssistance: { assist(entry) },
                              onSelection: { rating, assisted in record(entry, rating, assisted) }) { rating, assisted in
                    answer(entry, rating, assisted)
                }
            } else { missing(entry) }
        case .reading(let id):
            if let reading = model.pack.readings.first(where: { $0.id == id }) {
                ReadingCard(reading: reading, onAssistance: { assist(entry) },
                            onSelection: { rating, assisted in record(entry, rating, assisted) }) { rating, assisted in
                    answer(entry, rating, assisted)
                }
            } else { missing(entry) }
        }
    }
    private func answer(_ entry: SessionEntry, _ rating: Int, _ assisted: Bool) {
        model.speech.stop()
        model.perform { try model.answer(entryID: entry.id, rating: rating, assisted: assisted) }
    }
    private func assist(_ entry: SessionEntry) {
        model.perform { try model.markAssisted(entryID: entry.id) }
    }
    private func record(_ entry: SessionEntry, _ rating: Int, _ assisted: Bool) {
        model.perform { try model.recordAnswer(entryID: entry.id, rating: rating, assisted: assisted) }
    }
    private func missing(_ entry: SessionEntry) -> some View {
        VStack(spacing: 16) {
            Text("这项内容暂时不可用，请结束本次安排并更新课程。")
            Button("结束本次安排") { model.perform { try model.finishSession(); dismiss() } }
        }
    }
}

private struct RecallCard: View {
    @EnvironmentObject private var model: AppModel
    let item: KnowledgeItem
    let skill: Skill
    let onAssistance: () -> Void
    let onAnswer: (Int, Bool) -> Void
    @AppStorage("showRomaji") private var showRomaji = false
    @AppStorage("voiceID") private var voiceID = ""
    @State private var answer = ""
    @State private var revealed = false
    @State private var assisted = false
    @State private var typedCorrect: Bool?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(skill.title, systemImage: skill == .reading ? "character.book.closed" : "text.book.closed")
                .font(.caption).foregroundColor(.secondary)
            Text(item.text).font(.system(.largeTitle, design: .default).weight(.medium))
            if skill == .meaning { Text(item.reading).font(.title3).foregroundColor(.secondary) }
            Text(skill == .reading ? "这个词怎么读？" : "这个词是什么意思？").font(.title3)
            if skill == .reading && !revealed {
                TextField("可以输入假名，也可以先在心中回答", text: $answer)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).disableAutocorrection(true)
                if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("检查读音") {
                        typedCorrect = AnswerChecker.matches(answer, reading: item.reading)
                        if typedCorrect == false { onAssistance() }
                        revealed = true
                    }.buttonStyle(.borderedProminent)
                }
            }
            if revealed {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.reading).font(.title2)
                    if showRomaji && !item.romaji.isEmpty { Text(item.romaji).foregroundColor(.secondary) }
                    Text(item.meaning).font(.headline)
                    Text(item.explanation).font(.callout).foregroundColor(.secondary)
                    if let correct = typedCorrect {
                        Label(correct ? "读音正确" : "再看一次读音，下次继续", systemImage: correct ? "checkmark.circle" : "arrow.counterclockwise")
                            .foregroundColor(correct ? .accentColor : .secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(Color(UIColor.secondarySystemBackground)).cornerRadius(14)
                HStack {
                    speechButton(slow: false)
                    speechButton(slow: true)
                }
                if assisted || typedCorrect == false {
                    Text(assisted ? "这次使用了提示，会安排再练一次。" : "答错的读音会安排再次复习。")
                        .font(.caption).foregroundColor(.secondary)
                    Button("继续", action: { onAnswer(1, assisted) }).buttonStyle(.borderedProminent)
                } else {
                    Text("回想刚才揭示答案前的表现").font(.caption).foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        grade("没记住", 1); grade("吃力想起", 2); grade("记住", 3); grade("很熟", 4)
                    }
                }
            } else {
                Button("揭示答案") { revealed = true }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("给我提示") { onAssistance(); assisted = true; revealed = true }.font(.callout)
            }
        }
    }
    private func grade(_ label: String, _ rating: Int) -> some View {
        Button(label) { onAnswer(rating, false) }.frame(maxWidth: .infinity).buttonStyle(.bordered)
    }
    private func speechButton(slow: Bool) -> some View {
        Button {
            model.perform { try model.speech.speak(item.reading, slow: slow, voiceID: voiceID) }
        } label: { Label(slow ? "慢速" : "朗读", systemImage: slow ? "tortoise" : "speaker.wave.2") }
            .buttonStyle(.bordered)
    }
}

private struct StructureCard: View {
    @EnvironmentObject private var model: AppModel
    let exercise: Exercise
    let sentence: AnnotatedSentence
    let onAssistance: () -> Void
    let onSelection: (Int, Bool) -> Void
    let onAnswer: (Int, Bool) -> Void
    @State private var assisted = false
    @State private var showHint = false
    @State private var selected: KnowledgeItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(exercise.transfer ? "换一个句子试试" : "读懂句子").font(.caption).foregroundColor(.secondary)
            RubyText(segments: sentence.segments) { id in lookup(id) }
            LookupMenu(sentenceIDs: [sentence.id]) { id in lookup(id) }
            if !showHint {
                Button("查看提示") { onAssistance(); showHint = true; assisted = true }.font(.callout)
            } else {
                Text(exercise.hint).font(.callout).foregroundColor(.secondary)
            }
            ChoiceQuestion(prompt: exercise.prompt, choices: exercise.choices, correctIndex: exercise.answerIndex,
                           explanation: sentence.translation + "\n\n" + exercise.explanation,
                           onSelection: { correct in onSelection(correct && !assisted ? 3 : 1, assisted) }) { correct in
                onAnswer(correct && !assisted ? 3 : 1, assisted)
            }
        }.sheet(item: $selected) { item in NavigationView { ItemDetailView(item: item) }.navigationViewStyle(.stack) }
    }
    private func lookup(_ id: String) { onAssistance(); assisted = true; selected = model.pack.item(id) }
}

private struct ReadingCard: View {
    @EnvironmentObject private var model: AppModel
    let reading: ReadingPassage
    let onAssistance: () -> Void
    let onSelection: (Int, Bool) -> Void
    let onAnswer: (Int, Bool) -> Void
    @State private var assisted = false
    @State private var showReading = false
    @State private var selected: KnowledgeItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("\(reading.genre) · \(reading.level)").font(.caption).foregroundColor(.secondary)
            Text(reading.title).font(.title2.bold())
            Toggle("显示注音", isOn: Binding(get: { showReading }, set: {
                showReading = $0
                if $0 { onAssistance(); assisted = true }
            }))
                .font(.callout)
            ForEach(reading.sentenceIDs.compactMap { model.pack.sentence($0) }) { sentence in
                RubyText(segments: sentence.segments, showReading: showReading) { id in lookup(id) }
            }
            LookupMenu(sentenceIDs: reading.sentenceIDs) { id in lookup(id) }
            ChoiceQuestion(prompt: reading.question, choices: reading.choices, correctIndex: reading.answerIndex,
                           explanation: reading.explanation,
                           onSelection: { correct in onSelection(correct ? 3 : 1, assisted) }) { correct in
                onAnswer(correct ? 3 : 1, assisted)
            }
        }.sheet(item: $selected) { item in NavigationView { ItemDetailView(item: item) }.navigationViewStyle(.stack) }
    }
    private func lookup(_ id: String) { onAssistance(); assisted = true; selected = model.pack.item(id) }
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
        } label: { Label("查看词语", systemImage: "text.book.closed") }.font(.callout)
    }
}

private struct ChoiceQuestion: View {
    let prompt: String
    let choices: [String]
    let correctIndex: Int
    let explanation: String
    let onSelection: (Bool) -> Void
    let onContinue: (Bool) -> Void
    @State private var selected: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt).font(.headline)
            ForEach(choices.indices, id: \.self) { index in
                Button { selected = index; onSelection(index == correctIndex) } label: {
                    HStack {
                        Text(choices[index]).multilineTextAlignment(.leading)
                        Spacer()
                        if selected != nil && index == correctIndex { Image(systemName: "checkmark.circle.fill") }
                        else if selected == index { Image(systemName: "xmark.circle") }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                }.buttonStyle(.plain).disabled(selected != nil)
            }
            if let selected = selected {
                Text(selected == correctIndex ? "理解正确" : "一起看一下这里的关系").font(.headline).foregroundColor(.accentColor)
                Text(explanation).font(.callout).foregroundColor(.secondary)
                Button("继续") { onContinue(selected == correctIndex) }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }
}
