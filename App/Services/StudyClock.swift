import Foundation
import Combine
import LearningCore

@MainActor final class StudyClock: ObservableObject {
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isManuallyPaused = false
    @Published private(set) var isRunning = false
    private(set) var sessionID: UUID?
    var onInterval: ((UUID, DateInterval) throws -> Void)?
    var onError: ((Error) -> Void)?
    private var accumulator = StudyTimeAccumulator()
    private var timer: Timer?
    private var visible = false
    private var foreground = true
    private let automaticallyTicks: Bool
    private let now: () -> Date
    private let uptime: () -> TimeInterval

    init(automaticallyTicks: Bool = true, now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.automaticallyTicks = automaticallyTicks; self.now = now; self.uptime = uptime
    }

    var pendingInterval: DateInterval? { accumulator.pendingInterval }

    func bind(sessionID id: UUID, recordedSeconds: TimeInterval) throws {
        if sessionID == id { return }
        try setVisible(false)
        accumulator = StudyTimeAccumulator(elapsedSeconds: recordedSeconds)
        sessionID = id; isManuallyPaused = false; publish()
    }
    func setVisible(_ value: Bool) throws { visible = value; try reconcile() }
    func setForeground(_ value: Bool) throws { foreground = value; try reconcile() }
    func pause() throws { isManuallyPaused = true; try reconcile() }
    func resume() throws {
        try flush()
        isManuallyPaused = false
        try reconcile()
    }

    func tick() {
        accumulator.sample(uptime: uptime())
        publish()
        if accumulator.pendingSeconds >= 15 {
            do { try flush() } catch { onError?(error) }
        }
    }

    func flush() throws {
        accumulator.sample(uptime: uptime())
        guard let interval = accumulator.pendingInterval, let id = sessionID else { publish(); return }
        do {
            guard let save = onInterval else { throw LearningError.invalid("暂时无法保存学习时间。") }
            try save(id, interval)
            accumulator.acknowledgePending()
            publish()
        } catch {
            accumulator.stop(uptime: uptime())
            isManuallyPaused = true
            invalidateTimer()
            publish()
            throw error
        }
    }

    private func reconcile() throws {
        let shouldRun = visible && foreground && !isManuallyPaused && sessionID != nil
        if shouldRun && !accumulator.isRunning {
            try flush()
            if accumulator.pendingSeconds < 0.001 { accumulator.acknowledgePending() }
            _ = accumulator.start(at: now(), uptime: uptime())
            if automaticallyTicks {
                let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.tick() }
                }
                timer = tick
                RunLoop.main.add(tick, forMode: .common)
            }
        } else if !shouldRun {
            accumulator.stop(uptime: uptime())
            invalidateTimer()
            try flush()
        }
        publish()
    }
    private func publish() {
        elapsedSeconds = accumulator.elapsedSeconds
        isRunning = accumulator.isRunning
    }
    private func invalidateTimer() { timer?.invalidate(); timer = nil }
}
