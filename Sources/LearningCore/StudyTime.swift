import Foundation

public enum StudyTime {
    /// Count the union of intervals, including a live unsaved interval. Two devices
    /// open at the same time must not double the learner's daily total.
    public static func seconds(events: [LearningEvent], within range: DateInterval? = nil,
                               sessionID: UUID? = nil, live: DateInterval? = nil) -> TimeInterval {
        var intervals = events.compactMap { event -> DateInterval? in
            guard event.kind == .studyTime, let seconds = event.durationSeconds,
                  seconds.isFinite, seconds > 0,
                  sessionID == nil || event.targetID == sessionID?.uuidString else { return nil }
            return DateInterval(start: event.timestamp.addingTimeInterval(-seconds), end: event.timestamp)
        }
        if let live = live { intervals.append(live) }
        intervals = intervals.compactMap { interval in
            guard let range = range else { return interval }
            let start = max(interval.start, range.start), end = min(interval.end, range.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in intervals {
            if let previous = current {
                if interval.start <= previous.end {
                    current = DateInterval(start: previous.start, end: max(previous.end, interval.end))
                } else {
                    total += previous.duration
                    current = interval
                }
            } else { current = interval }
        }
        return total + (current?.duration ?? 0)
    }

    public static func today(events: [LearningEvent], now: Date = Date(), calendar: Calendar = .current,
                             live: DateInterval? = nil) -> TimeInterval {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return 0 }
        return seconds(events: events, within: day, live: live)
    }

    public static func remainingSeconds(targetMinutes: Int, studiedSeconds: TimeInterval) -> TimeInterval {
        max(0, Double(max(0, targetMinutes)) * 60 - studiedSeconds)
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

/// Timing uses monotonic uptime; changing the device's wall clock never adds study time.
/// Pending intervals must be acknowledged only after the journal transaction succeeds.
public struct StudyTimeAccumulator {
    public private(set) var elapsedSeconds: TimeInterval
    public private(set) var pendingSeconds: TimeInterval = 0
    public private(set) var isRunning = false
    private var intervalStart: Date?
    private var lastUptime: TimeInterval?

    public init(elapsedSeconds: TimeInterval = 0) { self.elapsedSeconds = max(0, elapsedSeconds) }

    public mutating func start(at date: Date, uptime: TimeInterval) -> Bool {
        guard !isRunning, pendingSeconds == 0 else { return false }
        intervalStart = date; lastUptime = uptime; isRunning = true
        return true
    }
    public mutating func sample(uptime: TimeInterval) {
        guard isRunning, let previous = lastUptime, uptime.isFinite, uptime >= previous else { return }
        let delta = uptime - previous
        elapsedSeconds += delta; pendingSeconds += delta; lastUptime = uptime
    }
    public mutating func stop(uptime: TimeInterval) {
        sample(uptime: uptime)
        isRunning = false; lastUptime = nil
    }
    public var pendingInterval: DateInterval? {
        guard let start = intervalStart, pendingSeconds >= 0.001 else { return nil }
        return DateInterval(start: start, duration: pendingSeconds)
    }
    public mutating func acknowledgePending() {
        if isRunning, let start = intervalStart { intervalStart = start.addingTimeInterval(pendingSeconds) }
        else { intervalStart = nil }
        pendingSeconds = 0
    }
}
