import SwiftUI

struct HomeTab: View {
    var body: some View {
        HStack(spacing: 14) {
            NowPlayingCard().frame(maxWidth: .infinity)
            UpcomingEvents().frame(width: 190)
        }
    }
}

struct NowPlayingCard: View {
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var settings: Settings

    var body: some View {
        if let info = media.info {
            HStack(spacing: 16) {
                ArtworkView(size: 128, corner: 16)
                    .overlay(alignment: .bottomTrailing) {
                        if let icon = info.app.icon {
                            Image(nsImage: icon).resizable().frame(width: 26, height: 26).offset(x: 6, y: 6)
                        }
                    }
                    .shadow(color: settings.ambientLight ? media.accent.opacity(0.6) : .black.opacity(0.5), radius: 14)
                    .onTapGesture { media.openApp(info.app) }

                VStack(alignment: .leading, spacing: 6) {
                    Text(info.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(info.artist.isEmpty ? info.album : info.artist)
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let pos = media.position(at: ctx.date)
                        VStack(spacing: 2) {
                            ScrubBar(value: info.duration > 0 ? pos / info.duration : 0, tint: settings.tintControls ? media.accent : .white) { media.seek(to: $0 * info.duration) }
                            HStack {
                                Text(formatTime(pos))
                                Spacer()
                                Text("-" + formatTime(max(0, info.duration - pos)))
                            }
                            .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 14) {
                        IconButton(systemName: "shuffle", size: 13, tint: info.shuffle ? (settings.tintControls ? media.accent : .green) : .white.opacity(0.6)) { media.toggleShuffle() }
                        Spacer(minLength: 0)
                        IconButton(systemName: "backward.fill", size: 18) { media.previous() }
                        IconButton(systemName: info.isPlaying ? "pause.fill" : "play.fill", size: 26) { media.playPause() }
                        IconButton(systemName: "forward.fill", size: 18) { media.next() }
                        Spacer(minLength: 0)
                        EqualizerView(playing: info.isPlaying, color: settings.tintControls ? media.accent : .green).frame(width: 26)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(L("Nothing playing")).font(.headline)
                Text(L("Universal control (browsers, YouTube, Podcasts…)")).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    IconButton(systemName: "backward.fill") { SystemInput.send(.previous) }
                    IconButton(systemName: "playpause.fill", size: 22) { SystemInput.send(.playPause) }
                    IconButton(systemName: "forward.fill") { SystemInput.send(.next) }
                }
                HStack {
                    if MediaApp.spotify.appURL != nil { Button(L("Open Spotify")) { media.openApp(.spotify) } }
                    Button(L("Open Music")) { media.openApp(.music) }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct UpcomingEvents: View {
    @EnvironmentObject var cal: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TimelineView(.everyMinute) { ctx in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ctx.date.formatted(.dateTime.weekday(.wide)).capitalized)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.red)
                        Text(ctx.date.formatted(.dateTime.day().month(.wide)))
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                Spacer()
                IconButton(systemName: "calendar", size: 12) { cal.openCalendar() }
            }
            if !cal.authorized {
                Spacer()
                Button(L("Allow calendar access")) { cal.requestAccess() }.controlSize(.small)
                Spacer()
            } else if cal.events.isEmpty {
                Spacer()
                Text(L("No upcoming events 🎉")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(cal.events) { e in
                            HStack(alignment: .top, spacing: 7) {
                                RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: e.color)).frame(width: 3, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(timeLabel(e)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if let s = e.service {
                                    Button { cal.join(e) } label: {
                                        Text(s).font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Capsule().fill(Color.blue))
                                    }
                                    .buttonStyle(.plain)
                                    .help(L("Join meeting"))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func timeLabel(_ e: CalEvent) -> String {
        let day = Calendar.current.isDateInToday(e.start) ? "" : L("Tomorrow · ")
        if e.allDay { return day + L("All day") }
        let f = DateFormatter()
        f.timeStyle = .short
        return day + "\(f.string(from: e.start)) – \(f.string(from: e.end))"
    }
}
