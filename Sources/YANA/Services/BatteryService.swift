import Foundation
import IOKit.ps

@MainActor
final class BatteryService: ObservableObject {
    static let shared = BatteryService()

    @Published private(set) var level: Int = 100
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    @Published private(set) var hasBattery = false
    @Published private(set) var minutesRemaining: Int?

    private var timer: Timer?
    private var initialized = false

    func start() {
        guard timer == nil else { return }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { BatteryService.shared.update() }
        }
    }

    private func update() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d["Type"] as? String) == "InternalBattery" else { continue }
            hasBattery = true
            let cur = d["Current Capacity"] as? Int ?? 0
            let max = d["Max Capacity"] as? Int ?? 100
            let newLevel = max > 0 ? cur * 100 / max : cur
            let newPlugged = (d["Power Source State"] as? String) == "AC Power"
            let newCharging = d["Is Charging"] as? Bool ?? false
            let key = newPlugged ? "Time to Full Charge" : "Time to Empty"
            let mins = d[key] as? Int
            minutesRemaining = (mins ?? -1) > 0 ? mins : nil

            if initialized && newPlugged != pluggedIn {
                pluggedIn = newPlugged
                level = newLevel
                charging = newCharging
                NotchViewModel.shared.showPeek(.battery, duration: 2.5)
            } else if initialized && !newPlugged && newLevel != level && (newLevel == 20 || newLevel == 10) {
                level = newLevel
                NotchViewModel.shared.showPeek(.battery, duration: 3)
            }
            level = newLevel
            pluggedIn = newPlugged
            charging = newCharging
        }
        initialized = true
    }

    var icon: String {
        if charging || pluggedIn { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
