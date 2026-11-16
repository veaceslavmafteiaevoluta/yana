import Foundation
import Darwin

@MainActor
final class SystemStats: ObservableObject {
    static let shared = SystemStats()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: Double = 0
    let memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)

    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                if NotchViewModel.shared.state == .open { SystemStats.shared.update() }
            }
        }
    }

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    private func update() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if r == KERN_SUCCESS {
            let t = info.cpu_ticks
            let user = UInt64(t.0), sys = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
            let busy = user + sys + nice, total = busy + idle
            if let last = lastTicks, total > last.total {
                cpu = Double(busy - last.busy) / Double(total - last.total)
            }
            lastTicks = (busy, total)
        }

        var vm = vm_statistics64()
        var vcount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vcount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vcount)
            }
        }
        if vr == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            let used = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            memoryUsed = Double(used * UInt64(pageSize))
        }
    }

    // MARK: Quick actions
    func lockScreen() { SystemInput.keystroke(0x0C, flags: [.maskCommand, .maskControl]) }
    func displaySleep() { SystemInput.shell("/usr/bin/pmset", ["displaysleepnow"]) }
    func screenshot() { SystemInput.shell("/usr/sbin/screencapture", ["-iUc"]) }
    func toggleDarkMode() {
        AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }
    func openActivityMonitor() { SystemInput.shell("/usr/bin/open", ["-a", "Activity Monitor"]) }
    func openSettings() { SystemInput.shell("/usr/bin/open", ["-a", "System Settings"]) }
}
