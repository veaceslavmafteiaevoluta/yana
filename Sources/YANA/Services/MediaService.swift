import AppKit
import SwiftUI

enum MediaApp: String {
    case spotify, music
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var name: String { self == .spotify ? "Spotify" : L("Music") }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var icon: NSImage? { appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }
}

struct NowPlaying: Equatable {
    var app: MediaApp
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var artworkURL: String
    var volume: Double
    var shuffle: Bool
    var repeating: Bool
    var fetchedAt: Date
}

@MainActor
final class MediaService: ObservableObject {
    static let shared = MediaService()

    @Published private(set) var info: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var appVolumes: [MediaApp: Double] = [:]
    @Published private(set) var accent: Color = .green
    @Published private(set) var accentSecondary: Color = .blue

    private func setArtwork(_ img: NSImage?) {
        artwork = img
        guard let c = img?.ambientColor() else {
            withAnimation(.easeInOut(duration: 0.8)) { accent = .green; accentSecondary = .blue }
            return
        }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let second = NSColor(hue: (h + 0.08).truncatingRemainder(dividingBy: 1), saturation: s, brightness: v * 0.9, alpha: 1)
        withAnimation(.easeInOut(duration: 0.8)) { accent = Color(nsColor: c); accentSecondary = Color(nsColor: second) }
    }

    var isPlaying: Bool { info?.isPlaying ?? false }
    private var artworkKey = ""
    private var timer: Timer?
    /// A fetch is running on `AppleScript.queue`; another `refresh()` meanwhile only asks for one more round.
    private var refreshing = false
    private var refreshAgain = false
    /// Bumped by every control command: a fetch that started earlier may predate the command,
    /// so its result is dropped instead of undoing the optimistic update.
    private var commandGen = 0
    /// Latest slider value per app not yet sent (volume drags are coalesced into one script each).
    private var pendingVolume: [MediaApp: Int] = [:]

    private init() {
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MediaService.shared.refreshSoon() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MediaService.shared.refreshSoon() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { MediaService.shared.refresh() }
        }
        refresh()
    }

    func position(at date: Date) -> Double {
        guard let i = info else { return 0 }
        guard i.isPlaying else { return i.position }
        return min(i.duration, i.position + date.timeIntervalSince(i.fetchedAt))
    }

    func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { MediaService.shared.refresh() } }
    }

    /// Reads both players on `AppleScript.queue` and applies the result on the main thread.
    func refresh() {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        let gen = commandGen
        let running = [MediaApp.spotify, .music].filter(\.isRunning)
        AppleScript.queue.async {
            let s = running.contains(.spotify) ? MediaService.fetch(.spotify) : nil
            let m = running.contains(.music) ? MediaService.fetch(.music) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let svc = MediaService.shared
                    svc.refreshing = false
                    if gen == svc.commandGen { svc.apply(spotify: s, music: m) } else { svc.refreshAgain = true }
                    if svc.refreshAgain { svc.refreshAgain = false; svc.refresh() }
                }
            }
        }
    }

    private func apply(spotify s: NowPlaying?, music m: NowPlaying?) {
        var vols: [MediaApp: Double] = [:]
        if let s { vols[.spotify] = s.volume }
        if let m { vols[.music] = m.volume }
        if vols != appVolumes { appVolumes = vols }

        let candidates = [s, m].compactMap { $0 }
        let chosen = candidates.first(where: \.isPlaying)
            ?? candidates.first(where: { $0.app == info?.app })
            ?? candidates.first

        let previousTitle = info?.title
        let wasPlaying = info?.isPlaying ?? false
        if chosen?.title != info?.title || chosen?.isPlaying != info?.isPlaying || chosen?.app != info?.app
            || abs((chosen?.position ?? 0) - position(at: Date())) > 2 || chosen?.shuffle != info?.shuffle {
            info = chosen
        }
        if let c = chosen {
            loadArtwork(for: c)
            if Settings.shared.trackPeeks, c.isPlaying, wasPlaying || previousTitle != nil, previousTitle != c.title {
                NotchViewModel.shared.showPeek(.track, duration: 2.5)
            }
        } else {
            if artwork != nil { setArtwork(nil) }
            artworkKey = ""
        }
    }

    /// Runs on `AppleScript.queue`; the caller has already checked that the app is running.
    private nonisolated static func fetch(_ app: MediaApp) -> NowPlaying? {
        let script: String
        switch app {
        case .spotify:
            script = """
            tell application id "com.spotify.client"
                set pState to (player state as string)
                if pState is "stopped" then return "stopped"
                set t to current track
                return pState & "|||" & (name of t) & "|||" & (artist of t) & "|||" & (album of t) & "|||" & ((duration of t) / 1000) & "|||" & (player position) & "|||" & (artwork url of t) & "|||" & (sound volume) & "|||" & (shuffling) & "|||" & (repeating)
            end tell
            """
        case .music:
            script = """
            tell application id "com.apple.Music"
                set pState to (player state as string)
                if pState is "stopped" then return "stopped"
                set tName to ""
                set tArtist to ""
                set tAlbum to ""
                set tDur to 0
                set tPos to 0
                try
                    set t to current track
                    set tName to name of t
                    set tArtist to artist of t
                    set tAlbum to album of t
                    set tDur to duration of t
                end try
                try
                    set tPos to player position
                end try
                return pState & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tDur & "|||" & tPos & "|||" & "" & "|||" & (sound volume) & "|||" & (shuffle enabled) & "|||" & (song repeat as string)
            end tell
            """
        }
        guard let out = AppleScript.run(script)?.stringValue else { return nil }
        let p = out.components(separatedBy: "|||")
        guard p.count >= 10 else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return NowPlaying(app: app, title: p[1], artist: p[2], album: p[3],
                          duration: num(p[4]), position: num(p[5]),
                          isPlaying: p[0] == "playing", artworkURL: p[6],
                          volume: num(p[7]), shuffle: p[8] == "true",
                          repeating: p[9] == "true" || p[9] == "all" || p[9] == "one",
                          fetchedAt: Date())
    }

    private func loadArtwork(for i: NowPlaying) {
        let key = "\(i.app.rawValue)|\(i.title)|\(i.album)|\(i.artworkURL)"
        guard key != artworkKey else { return }
        artworkKey = key
        switch i.app {
        case .spotify:
            guard let url = URL(string: i.artworkURL) else { setArtwork(nil); return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let img = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if MediaService.shared.artworkKey == key { MediaService.shared.setArtwork(img) }
                    }
                }
            }.resume()
        case .music:
            AppleScript.queue.async {
                let d = AppleScript.run("""
                tell application id "com.apple.Music"
                    try
                        return raw data of artwork 1 of current track
                    end try
                end tell
                """)?.data
                let img = d.flatMap(NSImage.init(data:))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if MediaService.shared.artworkKey == key { MediaService.shared.setArtwork(img) }
                    }
                }
            }
        }
    }

    // MARK: Controls

    private func tell(_ app: MediaApp, _ cmd: String) {
        commandGen += 1
        AppleScript.runAsync("tell application id \"\(app.bundleID)\" to \(cmd)")
        refreshSoon()
    }

    func playPause() {
        guard let i = info else { SystemInput.send(.playPause); return }
        info?.isPlaying.toggle()
        info?.position = i.isPlaying ? position(at: Date()) : i.position
        info?.fetchedAt = Date()
        tell(i.app, "playpause")
    }
    func next() { if let i = info { tell(i.app, "next track") } else { SystemInput.send(.next) } }
    func previous() { if let i = info { tell(i.app, "previous track") } else { SystemInput.send(.previous) } }
    func seek(to seconds: Double) {
        guard let i = info else { return }
        info?.position = seconds
        info?.fetchedAt = Date()
        tell(i.app, "set player position to \(Int(seconds))")
    }
    func toggleShuffle() {
        guard let i = info else { return }
        info?.shuffle.toggle()
        tell(i.app, i.app == .spotify ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled")
    }
    func setVolume(_ v: Double, for app: MediaApp) {
        appVolumes[app] = v
        commandGen += 1
        let queued = pendingVolume[app] != nil
        pendingVolume[app] = Int(v)
        guard !queued else { return }   // the script already queued will send the latest value
        AppleScript.queue.async {
            let value = DispatchQueue.main.sync {
                MainActor.assumeIsolated { MediaService.shared.pendingVolume.removeValue(forKey: app) }
            }
            guard let value else { return }
            AppleScript.run("tell application id \"\(app.bundleID)\" to set sound volume to \(value)")
        }
    }
    func openApp(_ app: MediaApp) {
        guard let url = app.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
