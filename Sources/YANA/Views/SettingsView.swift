import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var escMonitor: Any?

    /// Places the window right below the open notch so the two never overlap.
    func placeBelowNotch() {
        guard let w = window, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let gap: CGFloat = 14
        let top = min(screen.visibleFrame.maxY, NotchViewModel.shared.openNotchBottom - gap)
        let bottom = screen.visibleFrame.minY + 10
        let height = max(320, min(640, top - bottom))
        let frame = NSRect(x: screen.frame.midX - w.frame.width / 2, y: top - height, width: w.frame.width, height: height)
        w.setFrame(frame, display: true, animate: w.isVisible)
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = L("YANA Settings")
            w.titlebarSeparatorStyle = .line
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView()
                .environmentObject(Settings.shared)
                .environmentObject(MediaService.shared)
                .environmentObject(CalendarService.shared)
                .environmentObject(ContactsService.shared))
            window = w
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                MainActor.assumeIsolated {
                    if e.keyCode == 53, NotchViewModel.shared.previewPinned {
                        NotchViewModel.shared.endPreview()
                        return nil
                    }
                    return e
                }
            }
        }
        placeBelowNotch()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NotchViewModel.shared.endPreview()
    }
}

struct SettingsView: View {
    @EnvironmentObject var s: Settings
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var cal: CalendarService
    @EnvironmentObject var contacts: ContactsService
    @ObservedObject private var vm = NotchViewModel.shared
    @StateObject private var refresh = Box(0)

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text("YANA").font(.title2.bold())
                        Text(L("Yet Another Notch App · a Dynamic Island for your Mac")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Button(vm.previewPinned ? L("Close preview") : L("Show preview")) { togglePreview() }
                            .buttonStyle(.borderedProminent)
                        if vm.previewPinned {
                            Text(L("or press Esc")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(L("Appearance")) {
                Toggle(L("Glass effect (open notch)"), isOn: $s.glassBackground)
                if s.glassBackground {
                    LabeledSlider(title: L("Glass darkness"), value: $s.glassDarkness, range: 0...0.8, format: { "\(Int($0 * 100))%" })
                    LabeledSlider(title: L("Fade from notch"), value: $s.glassFade, range: 8...100, format: { "\(Int($0)) pt" })
                }
                Toggle(L("Ambient light from artwork"), isOn: $s.ambientLight)
                if s.ambientLight {
                    LabeledSlider(title: L("Light intensity"), value: $s.ambientIntensity, range: 0.1...1, format: { "\(Int($0 * 100))%" })
                    Toggle(L("Pulse while playing"), isOn: $s.ambientPulse)
                }
                Toggle(L("Tint controls with the artwork color"), isOn: $s.tintControls)
                HStack {
                    Text(L("Current color"))
                    Spacer()
                    Circle().fill(media.accent).frame(width: 18, height: 18)
                        .shadow(color: media.accent, radius: 6)
                    Text(media.info?.title ?? L("no track")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button(L("Reset appearance")) { s.resetAppearance() }
            }

            Section(L("Notch alignment")) {
                Text(L("Fine-tune the shape so it matches your physical notch exactly. Each step is one pixel."))
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(value: $s.notchHeightOffset, in: -4...6, step: 0.5) {
                    HStack { Text(L("Height")); Spacer(); Text(String(format: "%+.1f pt", s.notchHeightOffset)).monospacedDigit().foregroundStyle(.secondary) }
                }
                Stepper(value: $s.notchWidthOffset, in: -6...6, step: 0.5) {
                    HStack { Text(L("Width")); Spacer(); Text(String(format: "%+.1f pt", s.notchWidthOffset)).monospacedDigit().foregroundStyle(.secondary) }
                }
                Button(L("Reset alignment")) { s.notchHeightOffset = 1; s.notchWidthOffset = 0 }
            }

            Section(L("Behavior")) {
                Toggle(L("Open on hover (otherwise on click)"), isOn: $s.hoverToOpen)
                Toggle(L("Trackpad haptic feedback"), isOn: $s.haptics)
                Toggle(L("Always show the live activity while playing"), isOn: $s.persistentEars)
                    .help(L("Keeps artwork and equalizer beside the notch. When menus are underneath, the ears step aside as the mouse reaches the menu bar."))
                Toggle(L("Launch YANA at login"), isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        refresh.value += 1
                    }))
            }

            Section(L("HUD & notifications")) {
                Toggle(L("Replace system HUD (volume/brightness)"), isOn: $s.replaceSystemHUD)
                Toggle(L("Show volume HUD"), isOn: $s.volumeHUD)
                Toggle(L("Show brightness HUD"), isOn: $s.brightnessHUD)
                Toggle(L("Show track changes"), isOn: $s.trackPeeks)
                Toggle(L("App notifications in the notch"), isOn: $s.notificationPeeks)
            }

            Section(L("Permissions")) {
                PermRow(title: L("Accessibility"), detail: L("Media keys, HUD, screen lock"), ok: Permissions.accessibility) {
                    Permissions.requestAccessibility(); Permissions.openPane("Privacy_Accessibility")
                }
                PermRow(title: L("Full Disk Access"), detail: L("SMS, calls, app notifications"), ok: Permissions.fullDisk) {
                    Permissions.openPane("Privacy_AllFiles")
                }
                PermRow(title: L("Calendar"), detail: L("Events and meetings"), ok: cal.authorized) {
                    cal.requestAccess(); Permissions.openPane("Privacy_Calendars")
                }
                PermRow(title: L("Contacts"), detail: L("Names in messages and calls"), ok: contacts.authorized) {
                    contacts.load(); Permissions.openPane("Privacy_Contacts")
                }
                PermRow(title: L("Location"), detail: L("Weather"), ok: !WeatherService.shared.denied) {
                    Permissions.openPane("Privacy_LocationServices")
                }
                PermRow(title: L("Automation"), detail: L("Spotify, Music, Messages"), ok: true) {
                    Permissions.openPane("Privacy_Automation")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button(L("Quit YANA")) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .id(refresh.value)
    }

    private func togglePreview() {
        if vm.previewPinned {
            vm.endPreview()
        } else {
            vm.startPreview(tab: media.info != nil ? .audio : .home)
            SettingsWindowController.shared.placeBelowNotch()
        }
    }
}

private struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: (Double) -> String
    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
        }
    }
}

private struct PermRow: View {
    var title: String
    var detail: String
    var ok: Bool
    var fix: () -> Void
    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(ok ? L("Open") : L("Grant"), action: fix).controlSize(.small)
        }
    }
}
