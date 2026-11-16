import AppKit
import CoreGraphics

/// Intercepts volume / brightness keys, applies the change itself and shows the
/// notch HUD instead of the native macOS overlay. Requires Accessibility.
@MainActor
final class HUDReplacer {
    static let shared = HUDReplacer()

    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private(set) var active = false

    // NX key types (IOKit/hidsystem/ev_keymap.h)
    private enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    func start() {
        guard tap == nil else { return }
        if !install() {
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated {
                    if HUDReplacer.shared.install() { HUDReplacer.shared.retryTimer?.invalidate() }
                }
            }
        }
    }

    @discardableResult
    private func install() -> Bool {
        guard tap == nil, AXIsProcessTrusted() else { return tap != nil }
        let mask: CGEventMask = (1 << 14) | (1 << CGEventType.keyDown.rawValue) // 14 = NSSystemDefined
        let callback: CGEventTapCallBack = { _, type, event, _ in
            MainActor.assumeIsolated { HUDReplacer.shared.handle(type: type, event: event) }
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: callback, userInfo: nil) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        active = true
        NSLog("[YANA] HUD replacer attivo")
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard Settings.shared.replaceSystemHUD else { return pass }

        let flags = event.flags
        let fine = flags.contains(.maskShift) && flags.contains(.maskAlternate)

        // Brightness keys on some Apple Silicon keyboards arrive as plain keyDown (F14/F15-style codes)
        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            switch code {
            case 144: return brightness(+1, fine: fine) ? nil : pass
            case 145: return brightness(-1, fine: fine) ? nil : pass
            default: return pass
            }
        }

        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
        let keyCode = (ns.data1 & 0xFFFF0000) >> 16
        let keyDown = ((ns.data1 & 0x0000FF00) >> 8) == 0xA
        guard let key = Key(rawValue: keyCode) else { return pass }

        // Swallow key-up too so the system never sees half a keypress.
        switch key {
        case .soundUp, .soundDown, .mute:
            guard AudioService.shared.canSetVolume else { return pass }
            if keyDown { volume(key, fine: fine, silent: flags.contains(.maskShift) && !fine) }
            return nil
        case .brightnessUp, .brightnessDown:
            guard BrightnessService.shared.available else { return pass }
            if keyDown { _ = brightness(key == .brightnessUp ? +1 : -1, fine: fine) }
            return nil
        }
    }

    private func volume(_ key: Key, fine: Bool, silent: Bool) {
        let audio = AudioService.shared
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        switch key {
        case .mute:
            audio.setMuted(!audio.muted)
        case .soundUp:
            let base = audio.muted ? 0 : audio.volume
            audio.setVolume(snap(base + step, step))
        case .soundDown:
            if !audio.muted {
                let v = snap(audio.volume - step, step)
                audio.setVolume(v)
                if v <= 0.001 { audio.setMuted(true) }
            }
        default: break
        }
        if !silent { playFeedback() }
        NotchViewModel.shared.showPeek(.volume)
    }

    @discardableResult
    private func brightness(_ dir: Float, fine: Bool) -> Bool {
        let b = BrightnessService.shared
        guard b.available else { return false }
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        b.set(snap(b.brightness + dir * step, step))
        NotchViewModel.shared.showPeek(.brightness)
        return true
    }

    private func snap(_ v: Float, _ step: Float) -> Float {
        max(0, min(1, (v / step).rounded() * step))
    }

    /// Respects "Play feedback when volume is changed" in System Settings.
    private func playFeedback() {
        let enabled = UserDefaults(suiteName: ".GlobalPreferences")?.object(forKey: "com.apple.sound.beep.feedback") as? Int ?? 0
        guard enabled == 1 else { return }
        let path = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: path) { NSSound(contentsOfFile: path, byReference: true)?.play() }
    }
}
