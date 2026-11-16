import SwiftUI
import AppKit

struct ArtworkView: View {
    @EnvironmentObject var media: MediaService
    var size: CGFloat
    var corner: CGFloat = 6

    var body: some View {
        ZStack {
            if let img = media.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct EqualizerView: View {
    var playing: Bool
    var color: Color = .green
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = sin(t * (5 + Double(i) * 1.7) + Double(i) * 1.3)
                    Capsule().fill(color)
                        .frame(width: 3, height: playing ? 4 + 9 * CGFloat((phase + 1) / 2) : 3)
                }
            }
        }
        .frame(height: 14)
    }
}

struct LevelBar: View {
    var value: Double
    var color: Color = .white
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(color).frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: 5)
    }
}

/// Draggable progress bar.
struct ScrubBar: View {
    var value: Double          // 0...1
    var tint: Color = .white
    var onCommit: (Double) -> Void
    @StateObject private var drag = Box<Double?>(nil)

    var body: some View {
        GeometryReader { g in
            let v = drag.value ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(0, min(1, v)) * g.size.width)
                    .shadow(color: tint == .white ? .clear : tint.opacity(0.8), radius: 4)
            }
            .frame(height: drag.value == nil ? 5 : 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag.value = max(0, min(1, $0.location.x / g.size.width)) }
                .onEnded { _ in
                    if let d = drag.value { onCommit(d) }
                    drag.value = nil
                })
            .animation(.easeOut(duration: 0.15), value: drag.value == nil)
        }
        .frame(height: 14)
    }
}

struct IconButton: View {
    var systemName: String
    var size: CGFloat = 16
    var tint: Color = .white
    var action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size + 14, height: size + 14)
                .background(Circle().fill(Color.white.opacity(hover.value ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
    }
}

struct Avatar: View {
    var name: String
    var size: CGFloat = 30
    var body: some View {
        let hue = Double(abs(name.hashValue % 360)) / 360
        Text(initials(name))
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.75),
                                                              Color(hue: hue, saturation: 0.6, brightness: 0.5)],
                                                     startPoint: .top, endPoint: .bottom)))
    }
}

struct PermissionCard: View {
    var icon: String
    var title: String
    var message: String
    var button: String
    var action: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button(button, action: action).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// Local view state without the @State macro (not available with Command Line Tools).
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}
