import SwiftUI
import AppKit

struct ShelfTab: View {
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(L("Drop files here")).font(.headline)
                Text(L("Drag a file onto the notch to keep it at hand, then drag it out or share it via AirDrop."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(.white.opacity(0.25)))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(text: L("%ld items", shelf.items.count))
                    Spacer()
                    Button { shelf.airDrop(shelf.items) } label: { Label("AirDrop", systemImage: "airplayaudio") }
                    Button(L("Clear")) { shelf.clear() }
                }
                .controlSize(.small)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shelf.items, id: \.self) { url in
                            VStack(spacing: 4) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 56, height: 56)
                                Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(2)
                                    .multilineTextAlignment(.center).frame(width: 80)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                            .onTapGesture(count: 2) { shelf.open(url) }
                            .contextMenu {
                                Button(L("Open")) { shelf.open(url) }
                                Button(L("Show in Finder")) { shelf.reveal(url) }
                                Button("AirDrop") { shelf.airDrop([url]) }
                                Divider()
                                Button(L("Remove from Shelf")) { shelf.remove(url) }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
