import Foundation
import LearningCore

struct FolderExchangeResult {
    let events: [LearningEvent]
    let pendingDownloads: Int
    let written: Int
}

enum FolderExchange {
    /// Called on a detached task: File Provider coordination must never block the UI.
    static func exchange(bookmark: Data, events: [LearningEvent], contentVersion: String) throws -> FolderExchangeResult {
        var stale = false
        let directory = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, directory.startAccessingSecurityScopedResource() else {
            throw LearningError.invalid("同步文件夹授权已失效，请在设置中重新选择。")
        }
        defer { directory.stopAccessingSecurityScopedResource() }
        return try exchange(directory: directory, events: events, contentVersion: contentVersion)
    }

    static func exchange(directory: URL, events: [LearningEvent], contentVersion: String) throws -> FolderExchangeResult {
        let manager = FileManager.default
        let directoryKeys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey, .isRegularFileKey]
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(directoryKeys),
                                                   options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "jplearnsync" }
        var remote: [LearningEvent] = []
        var pending = 0
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try file.resourceValues(forKeys: directoryKeys)
            guard values.isRegularFile == true else { continue }
            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus != .current,
               values.ubiquitousItemDownloadingStatus != .downloaded {
                try manager.startDownloadingUbiquitousItem(at: file)
                pending += 1
                continue
            }
            let data: Data = try coordinated(file, writing: false) { url in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 70_000_000 else { throw LearningError.invalid("同步文件过大：\(url.lastPathComponent)") }
                return try Data(contentsOf: url)
            }
            do { remote += try ArchiveCodec.decode(data).events }
            catch { throw LearningError.invalid("无法读取同步文件 \(file.lastPathComponent)：\(error.localizedDescription)") }
        }
        let merged = try EventMerge.merge(events, remote)
        let remoteIDs = Set(remote.map(\.id))
        let outgoing = events.filter { !remoteIDs.contains($0.id) }
        if !outgoing.isEmpty {
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jplearnsync")
            let archive = ExchangeArchive(events: outgoing, contentVersion: contentVersion)
            let data = try ArchiveCodec.encode(archive)
            try coordinated(destination, writing: true) { url in
                try data.write(to: url, options: .atomic)
            }
        }
        return FolderExchangeResult(events: merged, pendingDownloads: pending, written: outgoing.count)
    }

    private static func coordinated<T>(_ url: URL, writing: Bool, body: @escaping (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { location in
                result = Result { try body(location) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
                result = Result { try body(location) }
            }
        }
        if let error = coordinationError { throw error }
        guard let result = result else { throw LearningError.invalid("文件服务暂时不可用，请稍后重试。") }
        return try result.get()
    }
}
