import SwiftUI
import LearningCore

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("dailyMinutes") private var minutes = 20
    @State private var session = false
    private var dueCount: Int { (try? ReviewScheduler().due(events: model.events, pack: model.pack))?.count ?? 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(Date(), style: .date).font(.subheadline).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text("每天拾起一点，\n读懂更大的世界。").font(.largeTitle.bold())
                    Text("从读音、句子到完整的段落，按自己的节奏前进。")
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 0) {
                    metric("\(dueCount)", "待复习")
                    Spacer()
                    metric("\(model.snapshot.reviewedToday())", "今日练习")
                    Spacer()
                    metric("\(minutes) 分钟", "学习安排")
                }.padding(20).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(18)
                Button {
                    model.perform { try model.startToday(minutes: minutes); session = model.checkpoint != nil }
                } label: {
                    Label(model.checkpoint == nil ? "开始学习" : "继续上次学习", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                VStack(alignment: .leading, spacing: 8) {
                    Label("今天的节奏", systemImage: "leaf")
                    Text("先复习，再学少量新内容，最后读一段短文。需要休息时随时离开，答案会逐项保存。")
                        .font(.callout).foregroundColor(.secondary)
                }
                if let lesson = model.pack.lessons.first(where: { !model.snapshot.completedLessons.contains($0.id) }) {
                    NavigationLink(destination: LessonDetailView(lesson: lesson)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("接着学习").font(.caption).foregroundColor(.secondary)
                                Text(lesson.title).font(.headline).foregroundColor(.primary)
                                Text(lesson.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }.padding(18).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16)
                    }
                }
                Text(model.pack.notice).font(.footnote).foregroundColor(.secondary)
            }.padding(24)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("今天").navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $session) { NavigationView { SessionView() }.navigationViewStyle(.stack) }
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title3.bold()).foregroundColor(.accentColor)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}

struct CourseView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Section {
                Text("把基础连成阅读能力").font(.title3.bold())
                Text("读音与词义分别练习；结构理解之后，再到新的句段中尝试。")
                    .font(.callout).foregroundColor(.secondary)
            }
            ForEach(model.pack.stages) { stage in
                Section(header: Text(stage.title)) {
                    Text(stage.summary).font(.callout).foregroundColor(.secondary)
                    let lessons = model.pack.lessons.filter { $0.level.lowercased() == stage.id }
                    ForEach(lessons) { lesson in
                        NavigationLink(destination: LessonDetailView(lesson: lesson)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(lesson.title)
                                    Text(lesson.subtitle).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if model.snapshot.completedLessons.contains(lesson.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                                        .accessibilityLabel("已完成")
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                    if lessons.isEmpty { Text("课程正在制作中").foregroundColor(.secondary) }
                    Text("制作目标：新增 \(stage.vocabularyTarget) 个词、\(stage.grammarTarget) 个表达、\(stage.readingTarget) 篇短文")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }.listStyle(.insetGrouped).navigationTitle("课程")
    }
}

struct LessonDetailView: View {
    @EnvironmentObject private var model: AppModel
    let lesson: Lesson
    @State private var session = false
    var body: some View {
        List {
            Section {
                Text(lesson.subtitle).foregroundColor(.secondary)
                Button {
                    model.perform { try model.startLesson(lesson); session = model.checkpoint != nil }
                } label: { Label("练习本单元", systemImage: "play.fill") }
                if model.checkpoint != nil {
                    Button("继续上次练习") { model.perform { try model.resumeSession(); session = true } }
                }
            }
            Section(header: Text("词汇与表达")) {
                ForEach(lesson.itemIDs.compactMap { model.pack.item($0) }) { item in
                    NavigationLink(destination: ItemDetailView(item: item)) { ItemRow(item: item) }
                }
            }
            Section(header: Text("例句与拆解")) {
                ForEach(lesson.sentenceIDs.compactMap { model.pack.sentence($0) }) { sentence in
                    SentenceView(sentence: sentence)
                }
            }
            if let id = lesson.readingID, let reading = model.pack.readings.first(where: { $0.id == id }) {
                Section(header: Text("短篇阅读")) {
                    NavigationLink(reading.title, destination: PassagePreview(reading: reading))
                }
            }
        }
        .navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $session) { NavigationView { SessionView() }.navigationViewStyle(.stack) }
    }
}

struct SentenceView: View {
    @EnvironmentObject private var model: AppModel
    let sentence: AnnotatedSentence
    @AppStorage("showFurigana") private var showFurigana = true
    @AppStorage("voiceID") private var voiceID = ""
    @State private var selected: KnowledgeItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RubyText(segments: sentence.segments, showReading: showFurigana) { id in selected = model.pack.item(id) }
            HStack {
                Button { model.perform { try model.speech.speak(sentence.speechText ?? sentence.text, voiceID: voiceID) } } label: {
                    Label("朗读", systemImage: "speaker.wave.2")
                }
                Spacer()
                Menu("本句词语") {
                    ForEach(Array(Set(sentence.segments.compactMap(\.itemID))).sorted(), id: \.self) { id in
                        if let item = model.pack.item(id) { Button(item.text) { selected = item } }
                    }
                }
            }.font(.callout).buttonStyle(.borderless)
            DisclosureGroup("中文与结构") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sentence.translation)
                    Text(sentence.explanation).font(.callout).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }.font(.callout)
        }.padding(.vertical, 8)
            .sheet(item: $selected) { item in NavigationView { ItemDetailView(item: item) }.navigationViewStyle(.stack) }
    }
}

struct PassagePreview: View {
    @EnvironmentObject private var model: AppModel
    let reading: ReadingPassage
    var body: some View {
        List {
            Section { Text("\(reading.level) · \(reading.genre)").font(.caption).foregroundColor(.secondary) }
            Section {
                ForEach(reading.sentenceIDs.compactMap { model.pack.sentence($0) }) { SentenceView(sentence: $0) }
            }
            Section(header: Text("想一想")) {
                Text(reading.question)
                DisclosureGroup("查看参考答案") { Text(reading.explanation).padding(.vertical, 8) }
            }
        }.navigationTitle(reading.title).navigationBarTitleDisplayMode(.inline)
    }
}
