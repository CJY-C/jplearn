import SwiftUI
import LearningCore

@MainActor final class AppModel: ObservableObject {
    let pack: ContentPack
    let speech = SpeechService()
    let deviceID: UUID
    private let store: EventStore
    private let checkpointURL: URL
    @Published private(set) var events: [LearningEvent]
    @Published private(set) var checkpoint: SessionCheckpoint?
    @Published var errorMessage: String?
    @Published var isSyncing = false
    @Published var syncMessage = "尚未选择同步文件夹"
    @Published var folderName: String

    var snapshot: LearningSnapshot { LearningSnapshot(events: events) }

    init() throws {
        pack = try ContentPack.bundled()
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "deviceID"), let id = UUID(uuidString: value) { deviceID = id }
        else { let generated = UUID(); deviceID = generated; defaults.set(generated.uuidString, forKey: "deviceID") }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let dataDirectory = directory.appendingPathComponent("JPLearn", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let eventStore = try EventStore(directory: dataDirectory)
        store = eventStore
        let loadedEvents = try eventStore.load()
        events = loadedEvents
        try ReviewScheduler().validateHistory(loadedEvents)
        let sessionURL = dataDirectory.appendingPathComponent("session.json")
        checkpointURL = sessionURL
        var checkpointIssue: String?
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            do {
                var restored = try ExchangeCoding.decoder().decode(SessionCheckpoint.self, from: Data(contentsOf: sessionURL))
                try restored.validate()
                restored.recover(recordedIDs: Set(loadedEvents.map(\.id)))
                checkpoint = restored
            } catch {
                checkpointIssue = "上次学习安排无法恢复。已完成的学习记录仍保留，可以重新开始。"
            }
        }
        folderName = defaults.string(forKey: "folderName") ?? ""
        if !folderName.isEmpty { syncMessage = "本机已保存，可同步学习记录" }
        errorMessage = checkpointIssue
    }

    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    func append(_ incoming: [LearningEvent]) throws {
        // Validate scheduler replay before the store transaction, including imported records.
        let merged = try EventMerge.merge(events, incoming)
        try ReviewScheduler().validateHistory(merged)
        events = try store.append(incoming, existing: events)
    }

    func startToday(minutes: Int) throws {
        if checkpoint != nil { try resumeSession(); return }
        let tasks = try SessionPlanner.make(pack: pack, events: events, minutes: minutes)
        try saveCheckpoint(SessionCheckpoint(tasks: tasks))
    }

    func resumeSession() throws {
        guard var current = checkpoint else { return }
        current.recover(recordedIDs: Set(events.map(\.id)))
        try saveCheckpoint(current)
    }

    func startLesson(_ lesson: Lesson) throws {
        guard checkpoint == nil else { throw LearningError.invalid("请先继续或结束上一次练习，再开始这个单元。") }
        let due = Set(try ReviewScheduler().dueKeys(events: events, pack: pack))
        let introduced = Set(events.compactMap { event -> ReviewKey? in
            guard event.kind == .review, let skill = event.skill else { return nil }
            return ReviewKey(itemID: event.targetID, skill: skill)
        })
        var tasks: [SessionTask] = lesson.itemIDs.compactMap { pack.item($0) }.flatMap { item -> [SessionTask] in
            item.kind == "word" ? item.skills.map { .recall(ReviewKey(itemID: item.id, skill: $0)) } : []
        }
        // Known words remain available in the lesson, while scheduled due work stays on Today.
        tasks = tasks.filter { task in
            guard case .recall(let key) = task else { return true }
            return !introduced.contains(key) || due.contains(key)
        }
        tasks += lesson.exerciseIDs.map { .exercise($0) }
        if let readingID = lesson.readingID { tasks.append(.reading(readingID)) }
        try saveCheckpoint(SessionCheckpoint(tasks: tasks, lessonID: lesson.id))
    }

    func markAssisted(entryID: UUID) throws {
        guard var current = checkpoint, current.current?.id == entryID,
              !events.contains(where: { $0.id == entryID }) else { return }
        current.assistedEntryIDs.insert(entryID)
        try saveCheckpoint(current)
    }

    func recordAnswer(entryID: UUID, rating: Int, assisted: Bool) throws {
        guard let current = checkpoint?.current, current.id == entryID else { return }
        let wasAssisted = assisted || (checkpoint?.assistedEntryIDs.contains(entryID) ?? false)
        if !events.contains(where: { $0.id == entryID }) {
            let event: LearningEvent
            switch current.task {
            case .recall(let key):
                event = LearningEvent(id: entryID, deviceID: deviceID, kind: .review, targetID: key.itemID,
                                      skill: key.skill, rating: rating, assisted: wasAssisted)
            case .exercise(let id):
                guard let exercise = pack.exercise(id) else { throw LearningError.invalid("练习内容缺失。") }
                event = LearningEvent(id: entryID, deviceID: deviceID, kind: .review, targetID: exercise.targetID,
                                      skill: .grammar, rating: rating, assisted: wasAssisted)
            case .reading(let id):
                event = LearningEvent(id: entryID, deviceID: deviceID, kind: .readingAttempt, targetID: id,
                                      assisted: wasAssisted, value: rating > 1 && !wasAssisted ? "correct" : "incorrect")
            }
            try append([event])
        }
    }

    func answer(entryID: UUID, rating: Int, assisted: Bool) throws {
        guard checkpoint?.current?.id == entryID else { return }
        try recordAnswer(entryID: entryID, rating: rating, assisted: assisted)
        guard var next = checkpoint else { return }
        next.index += 1
        try saveCheckpoint(next)
        if next.index % 5 == 0 { Task { await sync() } }
    }

    func finishSession() throws {
        guard var current = checkpoint else { return }
        current.recover(recordedIDs: Set(events.map(\.id)))
        if current.current == nil, let lessonID = current.lessonID,
           !events.contains(where: { $0.id == current.id }) {
            try append([LearningEvent(id: current.id, deviceID: deviceID, kind: .lessonCompleted, targetID: lessonID)])
        }
        try saveCheckpoint(nil)
        Task { await sync() }
    }

    private func saveCheckpoint(_ value: SessionCheckpoint?) throws {
        if let value = value {
            try ExchangeCoding.encoder().encode(value).write(to: checkpointURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: checkpointURL.path) {
            try FileManager.default.removeItem(at: checkpointURL)
        }
        checkpoint = value
    }

    func bookmark(_ id: String) {
        perform { try append([LearningEvent(deviceID: deviceID, kind: .bookmark, targetID: id,
                                            value: snapshot.isBookmarked(id) ? "false" : "true")]) }
    }
    func saveNote(_ note: String, for id: String) throws {
        guard note != snapshot.note(id) else { return }
        try append([LearningEvent(deviceID: deviceID, kind: .note, targetID: id, value: note)])
    }
    func exportBackup() throws -> Data {
        try ArchiveCodec.encode(ExchangeArchive(events: events, contentVersion: pack.version))
    }
    func importBackup(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            result = Result {
                guard (try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 70_000_000 else {
                    throw LearningError.invalid("备份文件过大，未导入。")
                }
                return try Data(contentsOf: location)
            }
        }
        if let error = coordinationError { throw error }
        guard let result = result else { throw LearningError.invalid("无法打开备份。") }
        try append(ArchiveCodec.decode(result.get()).events)
        if var current = checkpoint {
            current.recover(recordedIDs: Set(events.map(\.id)))
            try saveCheckpoint(current)
        }
        syncMessage = "备份已合并，本机记录已保存"
    }

    func chooseFolder(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else { throw LearningError.invalid("无法访问所选文件夹。") }
        defer { url.stopAccessingSecurityScopedResource() }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: "syncBookmark")
        UserDefaults.standard.set(url.lastPathComponent, forKey: "folderName")
        folderName = url.lastPathComponent
        syncMessage = "已连接文件夹，等待交换记录"
    }
    func disconnectFolder() {
        UserDefaults.standard.removeObject(forKey: "syncBookmark")
        UserDefaults.standard.removeObject(forKey: "folderName")
        folderName = ""; syncMessage = "同步已关闭，本机记录已保存"
    }
    func sync() async {
        guard !isSyncing, let bookmark = UserDefaults.standard.data(forKey: "syncBookmark") else { return }
        isSyncing = true
        syncMessage = "正在交换学习记录…"
        defer { isSyncing = false }
        let local = events, version = pack.version
        do {
            let result = try await Task.detached(priority: .utility) {
                try FolderExchange.exchange(bookmark: bookmark, events: local, contentVersion: version)
            }.value
            // New answers may have been saved while the exchange was running.
            try append(result.events)
            let time = Date().formatted(date: .omitted, time: .shortened)
            syncMessage = result.pendingDownloads > 0
                ? "\(time) 已交换，另有 \(result.pendingDownloads) 个文件等待下载"
                : "\(time) 已与文件夹交换记录"
        } catch { syncMessage = "本机已保存；同步未完成：\(error.localizedDescription)" }
    }
}
