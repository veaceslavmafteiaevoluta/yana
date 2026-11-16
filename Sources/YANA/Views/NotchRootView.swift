import AppKit
import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var settings: Settings

    var body: some View {
        let size = vm.frameSize
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)
        let visible = vm.hasPhysicalNotch || vm.state != .closed || vm.showsEars

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(vm.state == .open && settings.glassBackground ? Color.clear : Color.black)
                if vm.state == .open && settings.glassBackground {
                    GlassBackground(notchHeight: vm.notchSize.height, darkness: settings.glassDarkness, fade: settings.glassFade)
                        .transition(.opacity)
                }
                content
                    .padding(.horizontal, vm.topRadius)
                    .frame(width: size.width, height: size.height, alignment: .top)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .shadow(color: shadowColor, radius: vm.state == .closed ? 10 : 14, y: vm.state == .closed ? 2 : 6)
            .opacity(visible ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(vm.spring, value: vm.state)
        .animation(vm.spring, value: media.isPlaying)
        .animation(vm.spring, value: timer.isActive)
        .animation(vm.spring, value: vm.earsFit)
    }

    private var shadowColor: Color {
        if vm.state == .closed {
            return settings.ambientLight && media.isPlaying && vm.earsFit ? media.accent.opacity(0.45 * settings.ambientIntensity) : .clear
        }
        return .black.opacity(0.45)
    }

    @ViewBuilder private var content: some View {
        switch vm.state {
        case .closed:
            ClosedNotchView()
                .transition(.opacity)
        case .peek:
            PeekView()
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        case .open:
            OpenNotchView()
                .frame(width: vm.openBodySize.width, height: vm.openBodySize.height, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
        }
    }
}

/// Frosted glass for the expanded area: pure black in the notch band, fading into blur below.
struct GlassBackground: View {
    var notchHeight: CGFloat
    var darkness: Double = 0.28
    var fade: Double = 36
    var body: some View {
        GeometryReader { g in
            let h = max(g.size.height, 1)
            let solidEnd = notchHeight / h
            let fadeEnd = min(1, (notchHeight + fade) / h)
            VisualEffectBlur()
                .overlay(Color.black.opacity(darkness))
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: solidEnd),
                    .init(color: .white, location: fadeEnd),
                    .init(color: .white, location: 1),
                ], startPoint: .top, endPoint: .bottom))
                .background(Color.black.mask(LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: solidEnd),
                    .init(color: .clear, location: fadeEnd),
                ], startPoint: .top, endPoint: .bottom)))
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ClosedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var timer: TimerService

    var body: some View {
        HStack(spacing: 0) {
            if !vm.earsFit {
                EmptyView()
            } else if media.isPlaying {
                ArtworkView(size: vm.notchSize.height - 12, corner: 5)
                    .padding(.leading, 8)
            } else if timer.isActive {
                Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                    .padding(.leading, 12)
            }
            Spacer(minLength: 0)
            if !vm.earsFit {
                EmptyView()
            } else if timer.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(formatTime(timer.remaining(at: ctx.date)))
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(timer.isRunning ? .orange : .secondary)
                }
                .padding(.trailing, 8)
            } else if media.isPlaying {
                EqualizerView(playing: true, color: settings.tintControls ? media.accent : .green)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: vm.notchSize.height)
    }
}

struct PeekView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var brightness: BrightnessService
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var media: MediaService

    var body: some View {
        switch vm.peek {
        case .volume:
            ears(left: Image(systemName: audio.volumeIcon).font(.system(size: 14, weight: .semibold)),
                 right: HStack(spacing: 6) { LevelBar(value: audio.muted ? 0 : Double(audio.volume)); Text("\(Int(((audio.muted ? 0 : audio.volume) * 100).rounded()))").font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 24, alignment: .trailing) }.frame(width: 84))
        case .brightness:
            ears(left: Image(systemName: "sun.max.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.yellow),
                 right: HStack(spacing: 6) { LevelBar(value: Double(brightness.brightness), color: .yellow); Text("\(Int((brightness.brightness * 100).rounded()))").font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 24, alignment: .trailing) }.frame(width: 84))
        case .battery:
            ears(left: Image(systemName: battery.icon).font(.system(size: 15)).foregroundStyle(battery.pluggedIn ? .green : (battery.level <= 20 ? .red : .white)),
                 right: Text("\(battery.level)%").font(.system(size: 13, weight: .semibold)).foregroundStyle(battery.pluggedIn ? .green : .white))
        case .track:
            tall(leading: AnyView(ArtworkView(size: vm.notchSize.height - 10, corner: 5)),
                 trailing: AnyView(EqualizerView(playing: media.isPlaying)),
                 title: media.info?.title ?? "", subtitle: media.info?.artist ?? "", icon: nil)
        case .message(let title, let body, _):
            tall(leading: AnyView(Image(systemName: "message.fill").foregroundStyle(.green)),
                 trailing: AnyView(Text(L("now")).font(.caption2).foregroundStyle(.secondary)),
                 title: title, subtitle: body, icon: title)
        case .call(let title, let body):
            tall(leading: AnyView(Image(systemName: "phone.down.fill").foregroundStyle(.red)),
                 trailing: AnyView(Text("iPhone").font(.caption2).foregroundStyle(.secondary)),
                 title: title, subtitle: body, icon: title)
        case .event(let title, let body):
            tall(leading: AnyView(Image(systemName: "calendar").foregroundStyle(.red)),
                 trailing: AnyView(Text(L("Reminder")).font(.caption2).foregroundStyle(.secondary)),
                 title: title, subtitle: body, icon: nil)
        case .notification(let n):
            tall(leading: AnyView(Group { if let i = n.icon { Image(nsImage: i).resizable().frame(width: 18, height: 18) } }),
                 trailing: AnyView(Text(n.appName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)),
                 title: n.title.isEmpty ? n.appName : n.title,
                 subtitle: [n.subtitle, n.body].filter { !$0.isEmpty }.joined(separator: " · "), icon: nil)
        case .none:
            EmptyView()
        }
    }

    private func ears<L: View, R: View>(left: L, right: R) -> some View {
        HStack(spacing: 0) {
            left.foregroundStyle(.white).frame(width: 60)
            Spacer(minLength: vm.notchSize.width)
            right.frame(width: 84).padding(.trailing, 12)
        }
        .frame(height: vm.notchSize.height)
    }

    private func tall(leading: AnyView, trailing: AnyView, title: String, subtitle: String, icon: String?) -> some View {
        VStack(spacing: 6) {
            HStack {
                leading.font(.system(size: 14)).padding(.leading, 12)
                Spacer(minLength: vm.notchSize.width)
                trailing.padding(.trailing, 14)
            }
            .frame(height: vm.notchSize.height)
            HStack(spacing: 10) {
                if let icon { Avatar(name: icon, size: 34) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}
