import Foundation

public enum EventKind: String, Codable { case review, lessonCompleted, bookmark, note, readingAttempt, studyTime }

public struct LearningEvent: Codable, Identifiable, Equatable {
    public let id: UUID
    public let deviceID: UUID
    public let timestamp: Date
    public let kind: EventKind
    public let targetID: String
    public let skill: Skill?
    public let rating: Int?
    public let assisted: Bool
    public let value: String?
    public let schedulerVersion: Int
    public let durationSeconds: TimeInterval?

    public init(id: UUID = UUID(), deviceID: UUID, timestamp: Date = Date(), kind: EventKind,
                targetID: String, skill: Skill? = nil, rating: Int? = nil,
                assisted: Bool = false, value: String? = nil, schedulerVersion: Int = 1,
                durationSeconds: TimeInterval? = nil) {
        self.id = id; self.deviceID = deviceID
        self.timestamp = Date(timeIntervalSince1970: (timestamp.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.kind = kind
        self.targetID = targetID; self.skill = skill; self.rating = rating
        self.assisted = assisted; self.value = value; self.schedulerVersion = schedulerVersion
        self.durationSeconds = durationSeconds.map { ($0 * 1000).rounded() / 1000 }
    }

    public func validate() throws {
        guard !targetID.isEmpty, targetID.count <= 200, timestamp.timeIntervalSince1970.isFinite,
              timestamp >= Date(timeIntervalSince1970: 0), timestamp < Date(timeIntervalSince1970: 4_102_444_800),
              (value?.utf8.count ?? 0) <= 100_000 else {
            throw LearningError.invalid("学习记录含有无效字段。")
        }
        switch kind {
        case .review:
            guard skill != nil, (1...4).contains(rating ?? 0), schedulerVersion == 1 else {
                throw LearningError.invalid("复习记录或调度版本不受支持，请先更新应用。")
            }
        case .bookmark: guard ["true", "false"].contains(value ?? "") else { throw LearningError.invalid("收藏记录无效。") }
        case .note: guard value != nil else { throw LearningError.invalid("笔记记录无效。") }
        case .readingAttempt: guard ["correct", "incorrect"].contains(value ?? "") else { throw LearningError.invalid("阅读记录无效。") }
        case .lessonCompleted: break
        case .studyTime:
            guard let seconds = durationSeconds, seconds.isFinite, seconds > 0, seconds <= 86_400,
                  timestamp.timeIntervalSince1970 >= seconds, skill == nil, rating == nil else {
                throw LearningError.invalid("学习时间记录无效。")
            }
        }
    }

    public static func ordered(_ a: LearningEvent, _ b: LearningEvent) -> Bool {
        if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
        if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString }
        return a.id.uuidString < b.id.uuidString
    }
}

public enum EventMerge {
    /// Validate the entire batch before returning changes. Colliding IDs never silently replace history.
    public static func merge(_ existing: [LearningEvent], _ incoming: [LearningEvent]) throws -> [LearningEvent] {
        var values: [UUID: LearningEvent] = [:]
        for event in existing + incoming {
            try event.validate()
            if let old = values[event.id], old != event { throw LearningError.invalid("发现编号相同、内容不同的记录，未导入该批数据。") }
            values[event.id] = event
        }
        return values.values.sorted(by: LearningEvent.ordered)
    }
}

public struct LearningSnapshot {
    public let events: [LearningEvent]
    public init(events: [LearningEvent]) { self.events = events.sorted(by: LearningEvent.ordered) }
    public var completedLessons: Set<String> { Set(events.filter { $0.kind == .lessonCompleted }.map(\.targetID)) }
    public func isBookmarked(_ id: String) -> Bool {
        events.last { $0.kind == .bookmark && $0.targetID == id }?.value == "true"
    }
    public func note(_ id: String) -> String {
        events.last { $0.kind == .note && $0.targetID == id }?.value ?? ""
    }
    public func reviewedToday(at now: Date = Date(), calendar: Calendar = .current) -> Int {
        events.filter { $0.kind == .review && calendar.isDate($0.timestamp, inSameDayAs: now) }.count
    }
}

public enum ExchangeCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

public struct ExchangeArchive: Codable {
    public let format: String
    public let schemaVersion: Int
    public let contentVersion: String
    public let createdAt: Date
    public let events: [LearningEvent]

    public init(events: [LearningEvent], contentVersion: String, createdAt: Date = Date()) {
        format = "dev.jplearn.events"; schemaVersion = 2; self.contentVersion = contentVersion
        self.createdAt = createdAt; self.events = events
    }
    public func encoded() throws -> Data {
        _ = try EventMerge.merge([], events)
        return try ExchangeCoding.encoder().encode(self)
    }
    public static func decode(_ data: Data) throws -> ExchangeArchive {
        guard data.count <= 50_000_000 else { throw LearningError.invalid("文件超过 50 MB，请分批导入。") }
        let archive = try ExchangeCoding.decoder().decode(Self.self, from: data)
        guard archive.format == "dev.jplearn.events", [1, 2].contains(archive.schemaVersion) else {
            throw LearningError.invalid("备份或同步文件版本不受支持，请先更新应用。")
        }
        _ = try EventMerge.merge([], archive.events)
        return archive
    }
}
