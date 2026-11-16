import Foundation
import AppKit

@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()

    @Published private(set) var endDate: Date?
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var label = L("Timer")
    private var tick: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date = Date()) -> TimeInterval {
        if let p = pausedRemaining { return p }
        guard let e = endDate else { return 0 }
        return max(0, e.timeIntervalSince(date))
    }
    var progress: Double { total > 0 ? 1 - remaining() / total : 0 }

    func start(minutes: Double, label: String = L("Timer")) {
        total = minutes * 60
        self.label = label
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(total)
        schedule()
    }

    func togglePause() {
        if let p = pausedRemaining {
            endDate = Date().addingTimeInterval(p)
            pausedRemaining = nil
            schedule()
        } else if endDate != nil {
            pausedRemaining = remaining()
            endDate = nil
            tick?.invalidate()
        }
    }

    func stop() {
        endDate = nil
        pausedRemaining = nil
        tick?.invalidate()
    }

    private func schedule() {
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let s = TimerService.shared
                if s.isRunning, s.remaining() <= 0 { s.finish() }
            }
        }
    }

    private func finish() {
        let l = label
        stop()
        NSSound(named: "Glass")?.play()
        NotchViewModel.shared.showPeek(.event(title: L("%@ finished", l), body: L("⏰ Time's up")), duration: 6)
    }
}
