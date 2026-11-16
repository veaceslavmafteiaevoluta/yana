import Foundation

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // Generale
    @Published var hoverToOpen: Bool { didSet { d.set(hoverToOpen, forKey: "hoverToOpen") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    // HUD e notifiche
    @Published var replaceSystemHUD: Bool { didSet { d.set(replaceSystemHUD, forKey: "replaceSystemHUD") } }
    @Published var volumeHUD: Bool { didSet { d.set(volumeHUD, forKey: "volumeHUD") } }
    @Published var brightnessHUD: Bool { didSet { d.set(brightnessHUD, forKey: "brightnessHUD") } }
    @Published var notificationPeeks: Bool { didSet { d.set(notificationPeeks, forKey: "notificationPeeks") } }
    @Published var trackPeeks: Bool { didSet { d.set(trackPeeks, forKey: "trackPeeks") } }
    // Aspetto
    @Published var glassBackground: Bool { didSet { d.set(glassBackground, forKey: "glassBackground") } }
    @Published var glassDarkness: Double { didSet { d.set(glassDarkness, forKey: "glassDarkness") } }
    @Published var glassFade: Double { didSet { d.set(glassFade, forKey: "glassFade") } }
    @Published var ambientLight: Bool { didSet { d.set(ambientLight, forKey: "ambientLight") } }
    @Published var ambientIntensity: Double { didSet { d.set(ambientIntensity, forKey: "ambientIntensity") } }
    @Published var ambientPulse: Bool { didSet { d.set(ambientPulse, forKey: "ambientPulse") } }
    @Published var tintControls: Bool { didSet { d.set(tintControls, forKey: "tintControls") } }
    // Calibrazione forma (pt): compensa la differenza tra safe area e ritaglio fisico
    @Published var notchHeightOffset: Double { didSet { d.set(notchHeightOffset, forKey: "notchHeightOffset"); NotchViewModel.shared.updateScreen() } }
    @Published var notchWidthOffset: Double { didSet { d.set(notchWidthOffset, forKey: "notchWidthOffset"); NotchViewModel.shared.updateScreen() } }

    private init() {
        d.register(defaults: [
            "hoverToOpen": true, "haptics": true,
            "replaceSystemHUD": true, "volumeHUD": true, "brightnessHUD": true,
            "notificationPeeks": true, "trackPeeks": true,
            "glassBackground": true, "glassDarkness": 0.28, "glassFade": 36.0,
            "ambientLight": true, "ambientIntensity": 0.6, "ambientPulse": true, "tintControls": true,
            "notchHeightOffset": 1.0, "notchWidthOffset": 0.0,
        ])
        hoverToOpen = d.bool(forKey: "hoverToOpen")
        haptics = d.bool(forKey: "haptics")
        replaceSystemHUD = d.bool(forKey: "replaceSystemHUD")
        volumeHUD = d.bool(forKey: "volumeHUD")
        brightnessHUD = d.bool(forKey: "brightnessHUD")
        notificationPeeks = d.bool(forKey: "notificationPeeks")
        trackPeeks = d.bool(forKey: "trackPeeks")
        glassBackground = d.bool(forKey: "glassBackground")
        glassDarkness = d.double(forKey: "glassDarkness")
        glassFade = d.double(forKey: "glassFade")
        ambientLight = d.bool(forKey: "ambientLight")
        ambientIntensity = d.double(forKey: "ambientIntensity")
        ambientPulse = d.bool(forKey: "ambientPulse")
        tintControls = d.bool(forKey: "tintControls")
        notchHeightOffset = d.double(forKey: "notchHeightOffset")
        notchWidthOffset = d.double(forKey: "notchWidthOffset")
    }

    func resetAppearance() {
        glassBackground = true; glassDarkness = 0.28; glassFade = 36
        ambientLight = true; ambientIntensity = 0.6; ambientPulse = true; tintControls = true
    }
}
