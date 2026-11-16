import AppKit
import UniformTypeIdentifiers

@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [URL] = []
    private let key = "shelf.items"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map(URL.init(fileURLWithPath:)).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save() { UserDefaults.standard.set(items.map(\.path), forKey: key) }

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.append(u) }
        save()
    }
    func remove(_ url: URL) { items.removeAll { $0 == url }; save() }
    func clear() { items.removeAll(); save() }

    func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    /// Handles NSItemProviders coming from a SwiftUI drop.
    func handle(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                guard let url else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { ShelfStore.shared.add([url]) } }
            }
        }
        return accepted
    }
}
