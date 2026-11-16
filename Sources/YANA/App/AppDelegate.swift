import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private var statusItem: NSStatusItem!
    private let vm = NotchViewModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NotchPanel()
        let root = NotchRootView()
            .environmentObject(vm)
            .environmentObject(MediaService.shared)
            .environmentObject(AudioService.shared)
            .environmentObject(BrightnessService.shared)
            .environmentObject(BatteryService.shared)
            .environmentObject(CalendarService.shared)
            .environmentObject(ContactsService.shared)
            .environmentObject(MessagesService.shared)
            .environmentObject(CallService.shared)
            .environmentObject(ShelfStore.shared)
            .environmentObject(SystemStats.shared)
            .environmentObject(NotificationsService.shared)
            .environmentObject(WeatherService.shared)
            .environmentObject(TimerService.shared)
            .environmentObject(Settings.shared)
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        panel.contentView = host
        vm.attach(window: panel)
        panel.orderFrontRegardless()
        vm.updateScreen()

        AudioService.shared.start()
        BrightnessService.shared.start()
        BatteryService.shared.start()
        ContactsService.shared.load()
        CalendarService.shared.start()
        MessagesService.shared.start()
        CallService.shared.start()
        SystemStats.shared.start()
        NotificationsService.shared.start()
        WeatherService.shared.start()
        HUDReplacer.shared.start()
        _ = MediaService.shared

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchViewModel.shared.updateScreen() }
        }
        setupStatusItem()
        Screenshotter.runIfRequested(host: host)

        // Ask for Accessibility automatically only once; afterwards only from Settings / the menu.
        if !Permissions.accessibility && !UserDefaults.standard.bool(forKey: "didPromptAccessibility") {
            UserDefaults.standard.set(true, forKey: "didPromptAccessibility")
            Permissions.requestAccessibility()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "YANA")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: L("Open YANA"), action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())

        let perms = NSMenu()
        func add(_ title: String, _ ok: Bool, _ sel: Selector) {
            let it = NSMenuItem(title: (ok ? "✓ " : "✗ ") + title, action: sel, keyEquivalent: "")
            it.target = self
            perms.addItem(it)
        }
        add(L("Accessibility (media keys)"), Permissions.accessibility, #selector(openAX))
        add(L("Full Disk Access (SMS, calls)"), Permissions.fullDisk, #selector(openFDA))
        add(L("Calendar"), CalendarService.shared.authorized, #selector(openCal))
        add(L("Contacts"), ContactsService.shared.authorized, #selector(openContacts))
        add(L("Automation (Spotify, Music, Messages)"), true, #selector(openAutomation))
        let permItem = NSMenuItem(title: L("Permissions"), action: nil, keyEquivalent: "")
        permItem.submenu = perms
        menu.addItem(permItem)

        let prefs = NSMenu()
        let s = Settings.shared
        func toggle(_ title: String, _ on: Bool, _ sel: Selector) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            it.state = on ? .on : .off
            prefs.addItem(it)
        }
        toggle(L("Open on hover"), s.hoverToOpen, #selector(tHover))
        toggle(L("Glass effect (open notch)"), s.glassBackground, #selector(tGlass))
        toggle(L("Replace system HUD"), s.replaceSystemHUD, #selector(tReplace))
        toggle(L("Volume HUD"), s.volumeHUD, #selector(tVolume))
        toggle(L("Brightness HUD"), s.brightnessHUD, #selector(tBright))
        toggle(L("App notifications in the notch"), s.notificationPeeks, #selector(tNotif))
        toggle(L("Show track changes"), s.trackPeeks, #selector(tTrack))
        toggle(L("Haptic feedback"), s.haptics, #selector(tHaptic))
        let prefItem = NSMenuItem(title: L("Preferences"), action: nil, keyEquivalent: "")
        prefItem.submenu = prefs
        menu.addItem(prefItem)

        let login = NSMenuItem(title: L("Launch at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit YANA"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openNotch() { vm.open() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func tHover() { Settings.shared.hoverToOpen.toggle() }
    @objc private func tGlass() { Settings.shared.glassBackground.toggle() }
    @objc private func tReplace() { Settings.shared.replaceSystemHUD.toggle() }
    @objc private func tVolume() { Settings.shared.volumeHUD.toggle() }
    @objc private func tBright() { Settings.shared.brightnessHUD.toggle() }
    @objc private func tNotif() { Settings.shared.notificationPeeks.toggle() }
    @objc private func tTrack() { Settings.shared.trackPeeks.toggle() }
    @objc private func tHaptic() { Settings.shared.haptics.toggle() }
    @objc private func openAX() { Permissions.requestAccessibility(); Permissions.openPane("Privacy_Accessibility") }
    @objc private func openFDA() { Permissions.openPane("Privacy_AllFiles") }
    @objc private func openCal() { CalendarService.shared.requestAccess(); Permissions.openPane("Privacy_Calendars") }
    @objc private func openContacts() { ContactsService.shared.load(); Permissions.openPane("Privacy_Contacts") }
    @objc private func openAutomation() { Permissions.openPane("Privacy_Automation") }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Login item error: \(error)") }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.rebuildMenu() } }
    }
}
