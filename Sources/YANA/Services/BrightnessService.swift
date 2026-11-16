import Foundation
import CoreGraphics

@MainActor
final class BrightnessService: ObservableObject {
    static let shared = BrightnessService()

    @Published private(set) var brightness: Float = 0
    @Published private(set) var available = false

    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private var getFn: GetFn?
    private var setFn: SetFn?
    private var display: CGDirectDisplayID = CGMainDisplayID()
    private var timer: Timer?
    private var suppressUntil = Date.distantPast
    private var initialized = false

    func start() {
        guard timer == nil else { return }
        if let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) {
            if let g = dlsym(h, "DisplayServicesGetBrightness") { getFn = unsafeBitCast(g, to: GetFn.self) }
            if let s = dlsym(h, "DisplayServicesSetBrightness") { setFn = unsafeBitCast(s, to: SetFn.self) }
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &count)
        if let builtin = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) { display = builtin }
        available = getFn != nil
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { BrightnessService.shared.poll() }
        }
    }

    private func poll() {
        guard let getFn else { return }
        var v: Float = 0
        guard getFn(display, &v) == 0 else { return }
        if abs(v - brightness) > 0.004 {
            brightness = v
            if initialized, Date() > suppressUntil, Settings.shared.brightnessHUD { NotchViewModel.shared.showPeek(.brightness) }
        }
        initialized = true
    }

    func set(_ v: Float) {
        suppressUntil = Date().addingTimeInterval(0.6)
        brightness = v
        _ = setFn?(display, max(0, min(1, v)))
    }
}
