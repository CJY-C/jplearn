import SwiftUI
import LearningCore

struct ItemRow: View {
    let item: KnowledgeItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.text).font(.headline)
                if item.kind == "word" { Text(item.reading).font(.caption).foregroundColor(.secondary) }
                Spacer()
                Text(item.level).font(.caption2).foregroundColor(.secondary)
            }
            Text(item.meaning).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
        }.padding(.vertical, 4)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var filter = "全部"
    private var items: [KnowledgeItem] {
        model.pack.items.filter { item in
            let category = filter == "全部" || (filter == "词汇" && item.kind == "word") ||
                (filter == "表达" && item.kind == "grammar") || (filter == "收藏" && model.snapshot.isBookmarked(item.id))
            return category && (query.isEmpty || [item.text, item.reading, item.meaning, item.romaji]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    var body: some View {
        List {
            Section {
                Picker("显示内容", selection: $filter) {
                    ForEach(["全部", "词汇", "表达", "收藏"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section(header: Text("课程资料 · \(items.count) 项")) {
                if items.isEmpty { Text("没有匹配的内容").foregroundColor(.secondary) }
                ForEach(items) { item in NavigationLink(destination: ItemDetailView(item: item)) { ItemRow(item: item) } }
            }
        }
        .searchable(text: $query, prompt: "词、假名、罗马音或中文")
        .navigationTitle("资料")
    }
}

struct ItemDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: KnowledgeItem
    @AppStorage("showRomaji") private var showRomaji = false
    @AppStorage("voiceID") private var voiceID = ""
    @State private var note = ""
    @State private var saved = false
    var body: some View {
        List {
            Section {
                Text(item.text).font(.largeTitle)
                if !item.reading.isEmpty { Text(item.reading).font(.title3).foregroundColor(.secondary) }
                if showRomaji && !item.romaji.isEmpty { Text(item.romaji).foregroundColor(.secondary) }
                Text(item.meaning).font(.headline)
                HStack {
                    Button { speak(slow: false) } label: { Label("朗读", systemImage: "speaker.wave.2") }
                    Spacer()
                    Button("慢速") { speak(slow: true) }
                }.buttonStyle(.borderless)
            }
            Section(header: Text("理解与用法")) { Text(item.explanation) }
            Section(header: Text("学习记录")) {
                ForEach(item.skills) { skill in
                    let reviews = model.events.filter { $0.kind == .review && $0.targetID == item.id && $0.skill == skill }
                    HStack {
                        Text(skill.title)
                        Spacer()
                        Text(reviews.isEmpty ? "待学习" : "已练 \(reviews.count) 次").foregroundColor(.secondary)
                    }
                }
            }
            Section {
                Button { model.bookmark(item.id) } label: {
                    Label(model.snapshot.isBookmarked(item.id) ? "已收藏" : "收藏",
                          systemImage: model.snapshot.isBookmarked(item.id) ? "bookmark.fill" : "bookmark")
                }
            }
            Section(header: Text("我的笔记")) {
                TextEditor(text: $note).frame(minHeight: 100).accessibilityLabel("我的笔记")
                Button(saved ? "已保存" : "保存笔记") {
                    model.perform { try model.saveNote(note, for: item.id); saved = true }
                }.disabled(note == model.snapshot.note(item.id))
            }
            let examples = model.pack.sentences.filter { $0.segments.contains { $0.itemID == item.id } }
            if !examples.isEmpty {
                Section(header: Text("例句")) { ForEach(Array(examples.prefix(3))) { SentenceView(sentence: $0) } }
            }
            Section(header: Text("参考资料")) {
                ForEach(model.pack.references.filter { item.sourceIDs.contains($0.id) }) { reference in
                    if let url = URL(string: reference.url) { Link(reference.title, destination: url) }
                }
                Text(item.status == "trial" ? "个人试用内容，可在笔记中记录疑问。" : "已核对内容")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.navigationTitle(item.kind == "word" ? "词汇" : "表达").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { model.perform { try model.saveNote(note, for: item.id); dismiss() } }
                }
            }
            .onAppear { note = model.snapshot.note(item.id) }
            .onChange(of: note) { _ in saved = false }
            .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("好", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
    private func speak(slow: Bool) {
        let sample = model.pack.exercises.first { $0.targetID == item.id }
            .flatMap { model.pack.sentence($0.sentenceID) }
        let text = item.kind == "word" ? item.reading : (sample?.speechText ?? sample?.text ?? "")
        guard !text.isEmpty else { return }
        model.perform { try model.speech.speak(text, slow: slow, voiceID: voiceID) }
    }
}
