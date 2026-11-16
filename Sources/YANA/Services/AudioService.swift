import CoreAudio
import AudioToolbox
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32
    var icon: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        default: return "hifispeaker"
        }
    }
}

@MainActor
final class AudioService: ObservableObject {
    static let shared = AudioService()

    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var currentDevice: AudioDeviceID = 0

    private var listened = Set<AudioDeviceID>()
    private var suppressHUDUntil = Date.distantPast
    private var started = false

    private func addr(_ sel: AudioObjectPropertySelector,
                      _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private let system = AudioObjectID(kAudioObjectSystemObject)

    func start() {
        guard !started else { return }
        started = true
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(system, &a, .main) { _, _ in
            MainActor.assumeIsolated { AudioService.shared.reloadDevice() }
        }
        var d = addr(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(system, &d, .main) { _, _ in
            MainActor.assumeIsolated { AudioService.shared.reloadDeviceList() }
        }
        reloadDeviceList()
        reloadDevice()
    }

    private func reloadDevice() {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(system, &a, 0, nil, &size, &id)
        currentDevice = id
        readVolume(showHUD: false)
        guard !listened.contains(id) else { return }
        listened.insert(id)
        for sel in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var va = addr(sel, kAudioDevicePropertyScopeOutput)
            AudioObjectAddPropertyListenerBlock(id, &va, .main) { _, _ in
                MainActor.assumeIsolated {
                    if AudioService.shared.currentDevice == id { AudioService.shared.readVolume(showHUD: true) }
                }
            }
        }
    }

    private func readVolume(showHUD: Bool) {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        if AudioObjectHasProperty(currentDevice, &a) {
            AudioObjectGetPropertyData(currentDevice, &a, 0, nil, &size, &v)
        }
        var m = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        var ma = addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        if AudioObjectHasProperty(currentDevice, &ma) {
            AudioObjectGetPropertyData(currentDevice, &ma, 0, nil, &size, &m)
        }
        let changed = abs(v - volume) > 0.001 || (m != 0) != muted
        volume = v
        muted = m != 0
        if showHUD, changed, Date() > suppressHUDUntil, Settings.shared.volumeHUD {
            NotchViewModel.shared.showPeek(.volume)
        }
    }

    private func reloadDeviceList() {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids)

        devices = ids.compactMap { id in
            var sa = addr(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var ssize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ssize)
            guard ssize > 0 else { return nil }
            var na = addr(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let st = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(id, &na, 0, nil, &nsize, $0) }
            guard st == noErr, let n = name?.takeRetainedValue() as String? else { return nil }
            var ta = addr(kAudioDevicePropertyTransportType)
            var t = UInt32(0)
            var tsize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &ta, 0, nil, &tsize, &t)
            return AudioDevice(id: id, name: n, transport: t)
        }
    }

    func setVolume(_ v: Float) {
        suppressHUDUntil = Date().addingTimeInterval(0.6)
        var value = Float32(max(0, min(1, v)))
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(currentDevice, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        volume = value
        if muted && value > 0 { setMuted(false) }
    }

    func setMuted(_ m: Bool) {
        suppressHUDUntil = Date().addingTimeInterval(0.6)
        var value = UInt32(m ? 1 : 0)
        var a = addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(currentDevice, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        muted = m
    }

    func select(_ device: AudioDevice) {
        var id = device.id
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    var canSetVolume: Bool {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(currentDevice, &a),
              AudioObjectIsPropertySettable(currentDevice, &a, &settable) == noErr else { return false }
        return settable.boolValue
    }

    var volumeIcon: String {
        if muted || volume < 0.01 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
