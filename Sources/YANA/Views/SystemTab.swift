import SwiftUI

struct Ring: View {
    var value: Double
    var color: Color
    var label: String
    var detail: String
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: max(0.001, min(1, value)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: value)
                Text(detail).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 54, height: 54)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct SystemTab: View {
    @EnvironmentObject var stats: SystemStats
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var brightness: BrightnessService
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var cal: CalendarService
    @EnvironmentObject var contacts: ContactsService

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Ring(value: stats.cpu, color: .blue, label: "CPU", detail: "\(Int(stats.cpu * 100))%")
                    Ring(value: stats.memoryFraction, color: .purple, label: "RAM",
                         detail: String(format: "%.1fG", stats.memoryUsed / 1_073_741_824))
                    Ring(value: Double(battery.level) / 100, color: battery.pluggedIn ? .green : (battery.level <= 20 ? .red : .white),
                         label: battery.pluggedIn ? L("Charging") : L("Battery"), detail: "\(battery.level)%")
                }
                if let m = battery.minutesRemaining {
                    Text(battery.pluggedIn ? L("Full in %ldh %ldm", m / 60, m % 60) : L("%ldh %ldm remaining", m / 60, m % 60))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill").foregroundStyle(.yellow).frame(width: 18)
                        Slider(value: Binding(get: { Double(brightness.brightness) }, set: { brightness.set(Float($0)) }), in: 0...1)
                            .tint(.yellow).disabled(!brightness.available)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: audio.volumeIcon).frame(width: 18)
                        Slider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }), in: 0...1).tint(.white)
                    }
                }
            }
            .frame(width: 210)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                action("lock.fill", L("Lock")) { stats.lockScreen() }
                action("moon.fill", L("Display off")) { stats.displaySleep() }
                action("circle.lefthalf.filled", L("Theme")) { stats.toggleDarkMode() }
                action("camera.viewfinder", L("Screenshot")) { NotchViewModel.shared.close(); stats.screenshot() }
                action("waveform.path.ecg", L("Activity")) { stats.openActivityMonitor() }
                action("gearshape.fill", L("Settings")) { stats.openSettings() }
                action("capsule.fill", "YANA") { NotchViewModel.shared.close(); SettingsWindowController.shared.show() }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                SectionTitle(text: L("Permissions"))
                perm(L("Accessibility"), Permissions.accessibility) { Permissions.requestAccessibility(); Permissions.openPane("Privacy_Accessibility") }
                perm(L("Full Disk"), Permissions.fullDisk) { Permissions.openPane("Privacy_AllFiles") }
                perm(L("Calendar"), cal.authorized) { cal.requestAccess(); Permissions.openPane("Privacy_Calendars") }
                perm(L("Contacts"), contacts.authorized) { contacts.load(); Permissions.openPane("Privacy_Contacts") }
                perm(L("Automation"), true) { Permissions.openPane("Privacy_Automation") }
            }
            .frame(width: 120)
        }
    }

    private func action(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(.system(size: 9)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func perm(_ title: String, _ ok: Bool, _ fix: @escaping () -> Void) -> some View {
        Button(action: fix) {
            HStack(spacing: 5) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
                Text(title).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}
