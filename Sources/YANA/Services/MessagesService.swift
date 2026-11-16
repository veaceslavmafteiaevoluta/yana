import Foundation
import AppKit

struct ChatMessage: Identifiable, Equatable {
    let id: Int64
    let text: String
    let isFromMe: Bool
    let date: Date
    let handle: String
    let service: String
    let chatGuid: String
    let chatName: String
    let chatIdentifier: String
}

struct Conversation: Identifiable, Equatable {
    var id: String { guid }
    let guid: String
    let title: String
    let last: ChatMessage
    let unread: Bool
}

@MainActor
final class MessagesService: ObservableObject {
    static let shared = MessagesService()

    @Published private(set) var hasAccess = false
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var thread: [ChatMessage] = []
    @Published var selectedGuid: String? { didSet { loadThread() } }

    private let path = NSHomeDirectory() + "/Library/Messages/chat.db"
    private var db: SQLiteDB?
    private var lastRowID: Int64 = -1
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { MessagesService.shared.poll() }
        }
    }

    private func connection() -> SQLiteDB? {
        if db == nil { db = SQLiteDB(path: path) }
        return db
    }

    func poll() {
        guard let db = connection() else { hasAccess = false; return }
        var maxID: Int64 = 0
        let ok = db.query("SELECT IFNULL(MAX(ROWID),0) FROM message") { maxID = $0.int(0) }
        hasAccess = ok
        guard ok else { self.db = nil; return }
        guard maxID != lastRowID else { return }

        let isFirst = lastRowID < 0
        let previous = lastRowID
        lastRowID = maxID
        reload()
        if !isFirst {
            let fresh = fetch(where: "m.ROWID > \(previous) AND m.is_from_me = 0", limit: 3)
            if let m = fresh.first {
                let who = title(for: m)
                NotchViewModel.shared.showPeek(.message(title: who, body: m.text, chatGuid: m.chatGuid), duration: 5)
            }
        }
    }

    private func reload() {
        let rows = fetch(where: "1=1", limit: 400)
        var seen = Set<String>()
        var convs: [Conversation] = []
        for m in rows where !m.chatGuid.isEmpty && !seen.contains(m.chatGuid) {
            seen.insert(m.chatGuid)
            convs.append(Conversation(guid: m.chatGuid, title: title(for: m), last: m,
                                      unread: !m.isFromMe && Date().timeIntervalSince(m.date) < 3600))
            if convs.count >= 15 { break }
        }
        conversations = convs
        if selectedGuid == nil { selectedGuid = convs.first?.guid } else { loadThread() }
    }

    private func loadThread() {
        guard let g = selectedGuid else { thread = []; return }
        let safe = g.replacingOccurrences(of: "'", with: "''")
        thread = fetch(where: "c.guid = '\(safe)'", limit: 40).reversed()
    }

    func title(for m: ChatMessage) -> String {
        if !m.chatName.isEmpty { return m.chatName }
        let id = m.chatIdentifier.isEmpty ? m.handle : m.chatIdentifier
        return ContactsService.shared.displayName(for: id)
    }

    private func fetch(where clause: String, limit: Int) -> [ChatMessage] {
        guard let db = connection() else { return [] }
        let sql = """
        SELECT m.ROWID, m.text, m.attributedBody, m.is_from_me, m.date, IFNULL(h.id,''), IFNULL(m.service,''),
               IFNULL(c.guid,''), IFNULL(c.display_name,''), IFNULL(c.chat_identifier,''), IFNULL(m.cache_has_attachments,0)
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE m.associated_message_type = 0 AND m.item_type = 0 AND (\(clause))
        ORDER BY m.ROWID DESC LIMIT \(limit)
        """
        var out: [ChatMessage] = []
        db.query(sql) { r in
            var text = r.text(1) ?? ""
            if text.isEmpty, let blob = r.blob(2) { text = Self.decodeAttributedBody(blob) ?? "" }
            text = text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { text = r.int(10) != 0 ? L("📎 Attachment") : "…" }
            var raw = Double(r.int(4))
            if raw > 1_000_000_000_000 { raw /= 1_000_000_000 }
            out.append(ChatMessage(id: r.int(0), text: text, isFromMe: r.int(3) != 0,
                                   date: Date(timeIntervalSinceReferenceDate: raw),
                                   handle: r.text(5) ?? "", service: r.text(6) ?? "",
                                   chatGuid: r.text(7) ?? "", chatName: r.text(8) ?? "",
                                   chatIdentifier: r.text(9) ?? ""))
        }
        return out
    }

    /// Extracts the plain string from the typedstream-encoded NSAttributedString stored by Messages.
    static func decodeAttributedBody(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let r = bytes.firstRange(of: Array("NSString".utf8)) else { return nil }
        var i = r.upperBound + 5
        guard i < bytes.count else { return nil }
        var length = 0
        switch bytes[i] {
        case 0x81:
            guard i + 2 < bytes.count else { return nil }
            length = Int(bytes[i + 1]) | Int(bytes[i + 2]) << 8
            i += 3
        case 0x82:
            guard i + 4 < bytes.count else { return nil }
            length = Int(bytes[i + 1]) | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]) << 16 | Int(bytes[i + 4]) << 24
            i += 5
        default:
            length = Int(bytes[i])
            i += 1
        }
        guard length > 0, i + length <= bytes.count else { return nil }
        return String(decoding: bytes[i..<(i + length)], as: UTF8.self)
    }

    func send(_ text: String, to guid: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        AppleScript.run("""
        tell application "Messages"
            send "\(AppleScript.escape(t))" to chat id "\(AppleScript.escape(guid))"
        end tell
        """)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { MessagesService.shared.poll() } }
    }

    func openInMessages() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Messages.app"))
    }
}
