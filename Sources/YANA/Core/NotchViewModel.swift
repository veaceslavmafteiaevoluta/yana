import AppKit
import SwiftUI

enum NotchState: Equatable { case closed, peek, open }

enum PeekKind: Equatable {
    case volume
    case brightness
    case battery
    case track
    case message(title: String, body: String, chatGuid: String)
    case call(title: String, body: String)
    case event(title: String, body: String)
    case notification(AppNotification)

    var isTall: Bool {
        switch self {
        case .volume, .brightness, .battery: return false
        default: return true
        }
    }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, notifications, messages, phone, audio, widgets, shelf, system
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .notifications: return "bell.fill"
        case .widgets: return "cloud.sun.fill"
        case .messages: return "message.fill"
        case .phone: return "phone.fill"
        case .audio: return "speaker.wave.2.fill"
        case .shelf: return "tray.full.fill"
        case .system: return "cpu"
        }
    }
    var title: String {
        switch self {
        case .home: return L("Home")
        case .notifications: return L("Notifications")
        case .widgets: return L("Weather & Timer")
        case .messages: return L("Messages")
        case .phone: return L("Phone")
        case .audio: return L("Audio")
        case .shelf: return L("Shelf")
        case .system: return L("System")
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    static let shared = NotchViewModel()

    @Published var state: NotchState = .closed
    @Published var peek: PeekKind?
    @Published var tab: NotchTab = .home
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasPhysicalNotch = true
    @Published var pendingChatGuid: String?
    /// False when the live-activity ears would cover menus or status items (see MenuBarSpace).
    @Published private(set) var earsFit = true

    /// Keeps the notch open (e.g. while typing a reply).
    var keepOpen = false
    /// Notch pinned open by the settings preview.
    @Published var previewPinned = false

    let windowSize = CGSize(width: 780, height: 340)
    var openBodySize: CGSize { CGSize(width: 680, height: notchSize.height + 232 + (previewPinned ? 30 : 0)) }

    private weak var window: NSWindow?
    private var screen: NSScreen?
    private var timer: Timer?
    private var hoverSince: Date?
    private var leaveSince: Date?
    private var peekWork: DispatchWorkItem?
    private var lastDragCount = NSPasteboard(name: .drag).changeCount

    let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    // MARK: Geometry

    var topRadius: CGFloat { state == .open ? 14 : 7 }
    var bottomRadius: CGFloat {
        switch state {
        case .open: return 30
        case .peek: return (peek?.isTall ?? false) ? 24 : 12
        case .closed: return 10
        }
    }

    var earWidth: CGFloat { notchSize.height + 10 }

    /// The closed notch shows the live activity (artwork / timer on the sides) only if there's room for it.
    var showsEars: Bool { (MediaService.shared.isPlaying || TimerService.shared.isActive) && earsFit }

    var bodySize: CGSize {
        let w = notchSize.width, h = notchSize.height
        switch state {
        case .open:
            return openBodySize
        case .peek:
            if peek?.isTall ?? false { return CGSize(width: max(w + 220, 420), height: h + 66) }
            return CGSize(width: w + 200, height: h)
        case .closed:
            if showsEars { return CGSize(width: w + 2 * earWidth, height: h) }
            return CGSize(width: w, height: h)
        }
    }

    var frameSize: CGSize { CGSize(width: bodySize.width + 2 * topRadius, height: bodySize.height) }

    // MARK: Setup

    func attach(window: NSWindow) {
        self.window = window
        updateScreen()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { _ in
            MainActor.assumeIsolated { NotchViewModel.shared.tick() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchViewModel.shared.updateEarsFit() }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    MenuBarSpace.invalidateStatusItems()
                    // Status items appear a moment after the app launches.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        MainActor.assumeIsolated { MenuBarSpace.invalidateStatusItems(); NotchViewModel.shared.updateEarsFit() }
                    }
                }
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { NotchViewModel.shared.handleClick() }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            MainActor.assumeIsolated { NotchViewModel.shared.handleClick() }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { e in
            MainActor.assumeIsolated { NotchViewModel.shared.handleScroll(e) }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { e in
            MainActor.assumeIsolated { NotchViewModel.shared.handleScroll(e) }
            return e
        }
    }

    func updateScreen() {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let s = notched ?? NSScreen.main ?? NSScreen.screens.first
        screen = s
        guard let s else { return }
        if let notched, let l = notched.auxiliaryTopLeftArea, let r = notched.auxiliaryTopRightArea {
            hasPhysicalNotch = true
            let s = Settings.shared
            notchSize = CGSize(width: notched.frame.width - l.width - r.width + s.notchWidthOffset,
                               height: notched.safeAreaInsets.top + s.notchHeightOffset)
        } else {
            hasPhysicalNotch = false
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            notchSize = CGSize(width: 190, height: max(24, menuBar))
        }
        let f = NSRect(x: s.frame.midX - windowSize.width / 2, y: s.frame.maxY - windowSize.height,
                       width: windowSize.width, height: windowSize.height)
        window?.setFrame(f, display: true)
        debugLog("screen=\(s.frame) notch=\(notchSize) window=\(window?.frame ?? .zero)")
    }

    private func rect(for size: CGSize) -> NSRect {
        guard let s = screen else { return .zero }
        return NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
    }

    // MARK: Mouse tracking

    private var wasMouseDown = false
    private var ticks = 0
    private var wantedEars = false
    /// Menus or status items sit where the ears would go.
    private var menusUnderEars = false
    /// Persistent ears temporarily step aside so the menus underneath can be read and clicked.
    private var yielding = false
    private var yieldEndsAt: Date?

    /// Re-measures the menu bar around the notch (only matters while the live activity would be shown).
    /// Without `Settings.persistentEars` the ears hide while menus are underneath; with it they stay,
    /// and only step aside while the mouse is in the menu bar next to them (see `updateYield`).
    func updateEarsFit(force: Bool = false) {
        guard force || MediaService.shared.isPlaying || TimerService.shared.isActive, let s = screen else { return }
        let covered = !MenuBarSpace.earsFit(screen: s, notchWidth: notchSize.width, earWidth: earWidth + topRadius)
        if covered != menusUnderEars {
            menusUnderEars = covered
            debugLog("menu bar items \(covered ? "under" : "clear of") the live activity ears")
        }
        if !covered || !Settings.shared.persistentEars { yielding = false; yieldEndsAt = nil }
        applyEarsFit()
    }

    private func applyEarsFit() {
        let fit = !menusUnderEars || (Settings.shared.persistentEars && !yielding)
        if fit != earsFit { withAnimation(spring) { earsFit = fit } }
    }

    /// Mouse in the menu bar band beside the notch (over the ears or the menus around them) → ears step aside;
    /// they come back 0.8 s after the mouse leaves the band and no pull-down menu is open.
    private func updateYield(mouse: NSPoint, now: Date) {
        guard menusUnderEars, Settings.shared.persistentEars, state == .closed, let s = screen else { return }
        let band = max(notchSize.height, s.frame.maxY - s.visibleFrame.maxY)
        let reach = notchSize.width / 2 + earWidth + topRadius + 160
        let inBand = mouse.y >= s.frame.maxY - band && abs(mouse.x - s.frame.midX) <= reach
            && abs(mouse.x - s.frame.midX) > notchSize.width / 2
        if inBand {
            yieldEndsAt = nil
            if !yielding { yielding = true; applyEarsFit() }
        } else if yielding {
            if MenuBarSpace.menuIsOpen() { yieldEndsAt = nil; return }
            if let end = yieldEndsAt {
                if now >= end { yielding = false; yieldEndsAt = nil; applyEarsFit() }
            } else {
                yieldEndsAt = now.addingTimeInterval(0.8)
            }
        }
    }
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var scrollConsumed = false

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        defer { wasMouseDown = mouseDown }
        let now = Date()
        ticks += 1
        let wants = MediaService.shared.isPlaying || TimerService.shared.isActive
        if wants != wantedEars || (ticks % 20 == 0 && state == .closed) {
            wantedEars = wants
            updateEarsFit()
        }
        updateYield(mouse: mouse, now: now)

        switch state {
        case .closed, .peek:
            // Ears over menus: only the notch itself opens YANA, the ears' area belongs to the menus.
            let hotWidth = state == .closed && menusUnderEars ? notchSize.width : max(bodySize.width, notchSize.width)
            let hot = rect(for: CGSize(width: hotWidth + 2 * topRadius,
                                       height: max(bodySize.height, notchSize.height))).insetBy(dx: -4, dy: -2)
            guard hot.contains(mouse) else { hoverSince = nil; return }
            if mouseDown {
                let pb = NSPasteboard(name: .drag)
                if pb.changeCount != lastDragCount, pb.types?.contains(.fileURL) == true {
                    lastDragCount = pb.changeCount
                    open(tab: .shelf)
                } else if !Settings.shared.hoverToOpen, !wasMouseDown {
                    open()
                }
                hoverSince = nil
            } else if !Settings.shared.hoverToOpen {
                hoverSince = nil
            } else if let since = hoverSince {
                if now.timeIntervalSince(since) > 0.15 { open() }
            } else {
                hoverSince = now
            }
        case .open:
            let r = rect(for: frameSize).insetBy(dx: -24, dy: -24)
            if r.contains(mouse) || keepOpen || previewPinned || mouseDown {
                leaveSince = nil
            } else if let since = leaveSince {
                if now.timeIntervalSince(since) > 0.4 { close() }
            } else {
                leaveSince = now
            }
        }
    }

    /// Trackpad swipes: down on the notch opens it, up on the header closes it,
    /// left/right switches tabs (open) or skips tracks (closed, while playing).
    private func handleScroll(_ e: NSEvent) {
        if e.phase == .began || (e.phase.isEmpty && e.momentumPhase.isEmpty && abs(e.scrollingDeltaX) + abs(e.scrollingDeltaY) == 0) {
            scrollX = 0; scrollY = 0; scrollConsumed = false
        }
        if e.phase == .ended || e.phase == .cancelled { scrollX = 0; scrollY = 0; scrollConsumed = false; return }
        guard e.momentumPhase.isEmpty, !scrollConsumed else { return }
        let inv: CGFloat = e.isDirectionInvertedFromDevice ? 1 : -1
        scrollX += e.scrollingDeltaX * inv
        scrollY += e.scrollingDeltaY * inv   // > 0  ==> fingers moving down
        let mouse = NSEvent.mouseLocation
        let threshold: CGFloat = 28

        switch state {
        case .closed, .peek:
            let hot = rect(for: CGSize(width: frameSize.width + 40, height: max(frameSize.height, notchSize.height) + 10))
            guard hot.contains(mouse) else { return }
            if scrollY > threshold { scrollConsumed = true; open() }
            else if MediaService.shared.info != nil, abs(scrollX) > threshold * 1.5 {
                scrollConsumed = true
                if scrollX < 0 { MediaService.shared.next() } else { MediaService.shared.previous() }
                haptic()
            }
        case .open:
            var header = rect(for: frameSize)
            header.origin.y = header.maxY - notchSize.height - 6
            header.size.height = notchSize.height + 6
            guard header.contains(mouse) else { return }
            if scrollY < -threshold { scrollConsumed = true; close() }
            else if abs(scrollX) > threshold * 1.5 {
                scrollConsumed = true
                let all = NotchTab.allCases
                if let i = all.firstIndex(of: tab) {
                    let next = scrollX < 0 ? min(all.count - 1, i + 1) : max(0, i - 1)
                    withAnimation(.easeInOut(duration: 0.2)) { tab = all[next] }
                    haptic()
                }
            }
        }
    }

    func haptic() {
        guard Settings.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func handleClick() {
        guard state == .open, !keepOpen, !previewPinned else { return }
        if !rect(for: frameSize).contains(NSEvent.mouseLocation) { close() }
    }

    // MARK: Transitions

    func open(tab newTab: NotchTab? = nil) {
        peekWork?.cancel()
        if case .message(_, _, let guid)? = peek {
            tab = .messages
            pendingChatGuid = guid
        } else if case .call? = peek {
            tab = .phone
        } else if case .notification? = peek {
            tab = .notifications
        }
        if state != .open { haptic() }
        if let newTab { tab = newTab }
        hoverSince = nil
        leaveSince = nil
        withAnimation(spring) {
            peek = nil
            state = .open
        }
        window?.ignoresMouseEvents = false
    }

    func startPreview(tab: NotchTab) {
        previewPinned = true
        keepOpen = true
        open(tab: tab)
    }

    func endPreview() {
        guard previewPinned else { return }
        previewPinned = false
        keepOpen = false
        close()
    }

    /// Bottom edge (screen coords) of the open notch, used to keep other windows out of its way.
    var openNotchBottom: CGFloat {
        guard let s = screen else { return 0 }
        return s.frame.maxY - openBodySize.height
    }

    func close() {
        keepOpen = false
        window?.ignoresMouseEvents = true
        withAnimation(spring) {
            state = .closed
            peek = nil
        }
    }

    func showPeek(_ kind: PeekKind, duration: TimeInterval = 1.6) {
        guard state != .open else { return }
        peekWork?.cancel()
        if peek != kind || state != .peek {
            withAnimation(spring) {
                peek = kind
                state = .peek
            }
        }
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                let vm = NotchViewModel.shared
                guard vm.state == .peek else { return }
                withAnimation(vm.spring) {
                    vm.state = .closed
                    vm.peek = nil
                }
            }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
