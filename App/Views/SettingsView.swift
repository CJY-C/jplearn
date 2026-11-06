import SwiftUI
import UniformTypeIdentifiers
import LearningCore

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jplearnBackup] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
extension UTType {
    static let jplearnBackup = UTType(exportedAs: "dev.jplearn.backup", conformingTo: .json)
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyMinutes") private var minutes = 20
    @AppStorage("dailyNewWords") private var dailyNewWords = 10
    @AppStorage("showRomaji") private var showRomaji = false
    @AppStorage("showFurigana") private var showFurigana = true
    @AppStorage("voiceID") private var voiceID = ""
    @State private var selectFolder = false
    @State private var importFile = false
    @State private var exportFile = false
    @State private var backup = BackupDocument()
    @State private var notice: String?
    var body: some View {
        Form {
            Section(header: Text("学习节奏")) {
                Stepper("每天约 \(minutes) 分钟", value: $minutes, in: 5...60, step: 5)
                Stepper("每天最多 \(dailyNewWords) 项新词义", value: $dailyNewWords, in: 5...20, step: 5)
                Text("按实际学习时间完成目标。学习页在前台时计时，暂停、锁屏或离开时停止；同一天的多轮学习会累计。")
                    .font(.caption).foregroundColor(.secondary)
                Text("到期复习优先，每天最多引入 2 个新表达。没有合适内容时结束安排，不用重复阅读凑满时间。")
                    .font(.caption).foregroundColor(.secondary)
                Text("新词义包括新词和已学词的新用法；相同字形的不同用法会配例句区分，读音完全相同时不重复引入。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(header: Text("日语显示")) {
                Toggle("查阅时显示注音", isOn: $showFurigana)
                Toggle("显示罗马音辅助", isOn: $showRomaji)
            }
            Section(header: Text("系统日语朗读")) {
                Picker("声音", selection: $voiceID) {
                    Text("系统默认日语声音").tag("")
                    ForEach(model.speech.japaneseVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }
                Button("试播日语") {
                    model.perform { try model.speech.speak("少しずつ、日本語の本を読んでいます。", voiceID: voiceID) }
                }
                Text("可在系统“辅助功能 → 朗读内容 → 声音”中准备日语语音。准备后请开启飞行模式试播，确认离线可用。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(header: Text("iCloud Drive 同步")) {
                if !model.folderName.isEmpty { Label(model.folderName, systemImage: "folder") }
                Text(model.syncMessage).font(.callout).foregroundColor(.secondary)
                Button(model.folderName.isEmpty ? "选择同步文件夹" : "重新选择文件夹") { selectFolder = true }
                    .disabled(model.isSyncing)
                if !model.folderName.isEmpty {
                    Button { Task { await model.sync() } } label: {
                        HStack { Text("现在同步"); if model.isSyncing { Spacer(); ProgressView() } }
                    }.disabled(model.isSyncing)
                    Button("断开同步", role: .destructive) { model.disconnectFolder() }.disabled(model.isSyncing)
                }
                Text("在每台设备选择 iCloud Drive 中的同一个专用文件夹。应用打开时交换记录；云端传输可能需要等待。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(header: Text("备份与恢复")) {
                Button("导出学习备份") {
                    model.perform { backup = BackupDocument(data: try model.exportBackup()); exportFile = true }
                }
                Button("合并备份") { importFile = true }
                Text("合并会保留本机学习记录，重复记录只计入一次。备份包含笔记与收藏。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(header: Text("关于")) {
                Text("日语拾阶 · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                Text("课程 \(model.pack.version) · \(model.pack.wordCount) 个词 · \(model.pack.lessons.count) 个单元")
                    .font(.callout).foregroundColor(.secondary)
                Text(model.pack.notice).font(.caption).foregroundColor(.secondary)
                NavigationLink("学习方法与参考资料", destination: AboutView())
            }
        }
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        .sheet(isPresented: $selectFolder) {
            FolderPicker { url in
                model.perform { try model.chooseFolder(url) }
                Task { await model.sync() }
            }
        }
        .fileImporter(isPresented: $importFile, allowedContentTypes: [.jplearnBackup, .json]) { result in
            model.perform { try model.importBackup(result.get()); notice = "备份已合并。" }
        }
        .fileExporter(isPresented: $exportFile, document: backup, contentType: .jplearnBackup,
                      defaultFilename: "日语拾阶备份") { result in
            model.perform { _ = try result.get(); notice = "备份已导出。" }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("已完成", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("好", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPicker
        init(parent: FolderPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.onPick(url) }
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.dismiss() }
    }
}

private struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Section(header: Text("从记忆到阅读")) {
                Text("先回想再揭示答案，间隔一段时间后再练。在不同句子里理解同一表达，并逐渐减少注音与解释。")
                Text("“费力”表示已经想起答案；没有想起时请选择“忘记”。用了提示的练习会安排再次复习。")
                Text("短文理解单独记录，不作为词汇掌握的替代。系统朗读用于读音辅助。")
            }
            Section(header: Text("研究与工具")) {
                Link("2026 · 间隔练习与词汇知识", destination: URL(string: "https://pressto.amu.edu.pl/index.php/ssllt/article/view/49487")!)
                Link("2025 · 泛读研究元分析", destination: URL(string: "https://link.springer.com/article/10.1007/s10648-025-10068-6")!)
                Link("2025 · 词汇覆盖与阅读理解", destination: URL(string: "https://discovery.ucl.ac.uk/id/eprint/10216385/")!)
                Link("FSRS · 开源复习调度", destination: URL(string: "https://github.com/open-spaced-repetition/swift-fsrs")!)
                NavigationLink("开源许可", destination: LicenseView())
            }
            Section(header: Text("课程参考")) {
                ForEach(model.pack.references) { reference in
                    NavigationLink(reference.title, destination: SourceDetailView(reference: reference))
                }
                Text("中文说明、例句及练习为本项目编写的个人试用内容。尚未经过完整的独立日语审校。")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }.navigationTitle("学习方法").navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseView: View {
    private var notice: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "swift-fsrs · MIT License" }
        return text
    }
    var body: some View {
        ScrollView { Text(notice).font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
            .navigationTitle("开源许可").navigationBarTitleDisplayMode(.inline)
    }
}
