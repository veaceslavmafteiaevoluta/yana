import SwiftUI

struct AudioTab: View {
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var settings: Settings

    private var tint: Color { settings.tintControls && media.info != nil ? media.accent : .white }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if let info = media.info {
                    HStack(spacing: 10) {
                        ArtworkView(size: 34, corner: 8)
                            .shadow(color: settings.ambientLight ? media.accent.opacity(0.8) : .clear, radius: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(info.artist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        EqualizerView(playing: info.isPlaying, color: tint)
                        IconButton(systemName: info.isPlaying ? "pause.fill" : "play.fill", size: 13, tint: tint) { media.playPause() }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [media.accent.opacity(0.28), media.accentSecondary.opacity(0.08)],
                                             startPoint: .leading, endPoint: .trailing)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(media.accent.opacity(0.35), lineWidth: 0.5))
                }
                SectionTitle(text: L("System volume"))
                HStack(spacing: 8) {
                    IconButton(systemName: audio.volumeIcon, size: 13) { audio.setMuted(!audio.muted) }
                    Slider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }), in: 0...1)
                        .tint(tint)
                    Text("\(Int((audio.muted ? 0 : audio.volume) * 100))%").font(.system(size: 11)).monospacedDigit().frame(width: 34)
                }

                SectionTitle(text: L("Per-app volume"))
                if media.appVolumes.isEmpty {
                    Text(L("Open Spotify or Music to adjust their volume")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach([MediaApp.spotify, .music], id: \.self) { app in
                    if let v = media.appVolumes[app] {
                        HStack(spacing: 8) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                            Text(app.name).font(.system(size: 11)).frame(width: 50, alignment: .leading)
                            Slider(value: Binding(get: { v }, set: { media.setVolume($0, for: app) }), in: 0...100)
                                .tint(settings.tintControls && media.info?.app == app ? media.accent : (app == .spotify ? .green : .pink))
                            Text("\(Int(v))").font(.system(size: 11)).monospacedDigit().frame(width: 26)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 16) {
                    IconButton(systemName: "backward.fill", size: 13) { SystemInput.send(.previous) }
                    IconButton(systemName: "playpause.fill", size: 16) { SystemInput.send(.playPause) }
                    IconButton(systemName: "forward.fill", size: 13) { SystemInput.send(.next) }
                    Text(L("Universal control (any app)")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: L("Audio output"))
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(audio.devices) { d in
                            Button { audio.select(d) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: d.icon).frame(width: 18)
                                    Text(d.name).font(.system(size: 12)).lineLimit(1)
                                    Spacer()
                                    if d.id == audio.currentDevice { Image(systemName: "checkmark").foregroundStyle(tint == .white ? .blue : tint) }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(
                                    d.id == audio.currentDevice
                                        ? (tint == .white ? Color.white.opacity(0.12) : media.accent.opacity(0.25))
                                        : Color.white.opacity(0.04)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 230)
        }
    }
}
