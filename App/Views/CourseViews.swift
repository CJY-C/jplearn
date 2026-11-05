import SwiftUI
import LearningCore

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: StudyClock
    @Environment(\.sizeCategory) private var sizeCategory
    @AppStorage("dailyMinutes") private var minutes = 20
    @State private var session = false
    private var studied: TimeInterval { StudyTime.today(events: model.events, live: clock.pendingInterval) }
    private var reached: Bool { studied >= Double(minutes * 60) }
    private var dueCount: Int { (try? ReviewScheduler().dueKeys(events: model.events, pack: model.pack))?.count ?? 0 }
    var body: some View {
        Group {
            if sizeCategory.isAccessibilityCategory { ScrollView { content } }
            else { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                model.perform { try model.startToday(minutes: minutes); session = model.checkpoint != nil }
            } label: {
                Label(model.checkpoint != nil ? "继续学习" : (reached ? "继续巩固" : "开始学习"), systemImage: "arrow.right")
            }.buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("today.start")
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color(UIColor.systemGroupedBackground))
        }
        .navigationTitle("今天").navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $session) { NavigationView { SessionView() }.navigationViewStyle(.stack) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今天读一点").font(.title2.weight(.semibold))
                Spacer()
                Text(Date(), format: .dateTime.month().day()).font(.caption).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("今日学习").font(.subheadline.weight(.medium))
                    Spacer()
                    Text(reached ? "目标已完成" : "目标 \(minutes) 分钟")
                        .font(.caption).foregroundColor(reached ? .accentColor : .secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(StudyTime.clock(studied)).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                        .accessibilityIdentifier("today.studyTime")
                    Text("/ \(StudyTime.clock(Double(minutes * 60)))").font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
                }
                ProgressView(value: min(studied, Double(minutes * 60)), total: Double(minutes * 60))
            }.padding(18).background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack {
                metric("\(dueCount)", "待复习")
                Spacer()
                metric("\(model.snapshot.reviewedToday())", "今日练习")
                Spacer()
                Image(systemName: "leaf").foregroundColor(.accentColor)
            }.padding(.horizontal, 4)
            if let lesson = model.pack.lessons.first(where: { !model.snapshot.completedLessons.contains($0.id) }) {
                NavigationLink(destination: LessonDetailView(lesson: lesson)) {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed").foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("接着学习").font(.caption).foregroundColor(.secondary)
                            Text(lesson.title).font(.subheadline.weight(.medium)).foregroundColor(.primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }.padding(16).background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }.buttonStyle(.plain)
            }
            Text("学习时计时，暂停或离开时自动停下。")
                .font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 0)
        }.padding(.horizontal, 18).padding(.top, 14)
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.weight(.semibold))
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
                } label: { Label("练习本单元", systemImage: "arrow.right") }
                    .buttonStyle(StudyPrimaryButtonStyle())
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
