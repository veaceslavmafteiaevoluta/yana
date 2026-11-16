import AppKit

struct AppNotification: Identifiable, Equatable {
    let id: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    var appName: String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }
    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// Mirrors macOS Notification Center (all apps) by reading its database. Requires Full Disk Access.
@MainActor
final class NotificationsService: ObservableObject {
    static let shared = NotificationsService()

    @Published private(set) var hasAccess = false
    @Published private(set) var items: [AppNotification] = []
    /// Notifications dismissed in YANA (macOS offers no public API to remove them from Notification Center).
    @Published private(set) var dismissed: Set<Int64>
    /// Everything up to this rec_id was cleared with "Clear all".
    @Published private(set) var clearedUpTo: Int64
    /// Apps whose notifications never pop up in the notch.
    @Published private(set) var mutedApps: Set<String>

    /// What the Notifications tab shows.
    var visible: [AppNotification] { items.filter { $0.id > clearedUpTo && !dismissed.contains($0.id) } }

    /// Visible notifications grouped by app, newest app first.
    var groups: [(bundleID: String, items: [AppNotification])] {
        var order: [String] = []
        var map: [String: [AppNotification]] = [:]
        for n in visible {
            if map[n.bundleID] == nil { order.append(n.bundleID) }
            map[n.bundleID, default: []].append(n)
        }
        return order.map { ($0, map[$0]!) }
    }

    private let d = UserDefaults.standard
    private init() {
        dismissed = Set((d.array(forKey: "notifications.dismissed") as? [NSNumber] ?? []).map(\.int64Value))
        clearedUpTo = (d.object(forKey: "notifications.clearedUpTo") as? NSNumber)?.int64Value ?? 0
        mutedApps = Set(d.stringArray(forKey: "notifications.mutedApps") ?? [])
    }

    /// Apps already handled by dedicated modules (avoid duplicate peeks).
    private let skipPeek: Set<String> = ["com.apple.MobileSMS", "com.apple.iCal"]
    private var db: SQLiteDB?
    private var lastID: Int64 = -1
    private var timer: Timer?

    private let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { NotificationsService.shared.poll() }
        }
    }

    private func poll() {
        if db == nil { db = SQLiteDB(path: path) }
        guard let db else { hasAccess = false; return }
        var maxID: Int64 = 0
        let ok = db.query("SELECT IFNULL(MAX(rec_id),0) FROM record") { maxID = $0.int(0) }
        hasAccess = ok
        guard ok else { self.db = nil; return }
        guard maxID != lastID else { return }
        let first = lastID < 0
        let prev = lastID
        lastID = maxID

        var list: [AppNotification] = []
        db.query("""
        SELECT r.rec_id, IFNULL(a.identifier,''), r.data, IFNULL(r.delivered_date,0)
        FROM record r LEFT JOIN app a ON a.app_id = r.app_id
        ORDER BY r.rec_id DESC LIMIT 40
        """) { row in
            guard let data = row.blob(2), let n = Self.parse(id: row.int(0), app: row.text(1) ?? "", data: data, delivered: row.double(3)) else { return }
            list.append(n)
        }
        items = list
        // Forget dismissed ids that dropped out of the window, so the stored set stays small.
        if let oldest = list.last?.id {
            let kept = dismissed.filter { $0 >= oldest }
            if kept.count != dismissed.count { dismissed = kept; saveDismissed() }
        }
        guard !first, let newest = list.first(where: { $0.id > prev }) else { return }
        let b = newest.bundleID.lowercased()
        if b.contains("telephony") || b.contains("facetime") || b.contains("callservices") {
            // Continuity call from the iPhone (incoming / missed)
            NotchViewModel.shared.showPeek(.call(title: newest.title, body: newest.body.isEmpty ? newest.subtitle : newest.body), duration: 8)
        } else if Settings.shared.notificationPeeks, !skipPeek.contains(newest.bundleID), !mutedApps.contains(newest.bundleID) {
            NotchViewModel.shared.showPeek(.notification(newest), duration: 5)
        }
    }

    private static func parse(id: Int64, app: String, data: Data, delivered: Double) -> AppNotification? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let req = plist["req"] as? [String: Any] ?? [:]
        let title = req["titl"] as? String ?? ""
        let subtitle = req["subt"] as? String ?? ""
        let body = req["body"] as? String ?? ""
        guard !(title.isEmpty && body.isEmpty) else { return nil }
        let bundle = (plist["app"] as? String) ?? app
        let date = (plist["date"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) }
            ?? Date(timeIntervalSinceReferenceDate: delivered)
        return AppNotification(id: id, bundleID: bundle, title: title, subtitle: subtitle, body: body, date: date)
    }

    // MARK: Management (local to YANA)

    func dismiss(_ n: AppNotification) {
        dismissed.insert(n.id); saveDismissed()
    }

    func dismissAll(from bundleID: String) {
        for n in items where n.bundleID == bundleID { dismissed.insert(n.id) }
        saveDismissed()
    }

    func clearAll() {
        guard let top = items.first?.id else { return }
        clearedUpTo = top
        dismissed = []
        d.set(NSNumber(value: top), forKey: "notifications.clearedUpTo")
        saveDismissed()
    }

    func isMuted(_ bundleID: String) -> Bool { mutedApps.contains(bundleID) }

    func toggleMute(_ bundleID: String) {
        if mutedApps.contains(bundleID) { mutedApps.remove(bundleID) } else { mutedApps.insert(bundleID) }
        d.set(Array(mutedApps), forKey: "notifications.mutedApps")
    }

    func copy(_ n: AppNotification) {
        let text = [n.title, n.subtitle, n.body].filter { !$0.isEmpty }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveDismissed() {
        d.set(dismissed.map { NSNumber(value: $0) }, forKey: "notifications.dismissed")
    }

    func open(_ n: AppNotification) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
