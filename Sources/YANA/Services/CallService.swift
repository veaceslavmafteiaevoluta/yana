import Foundation
import AppKit

struct CallRecord: Identifiable, Equatable {
    let id: Int64
    let address: String
    let date: Date
    let duration: Double
    let outgoing: Bool
    let answered: Bool
    let type: Int
    var missed: Bool { !outgoing && !answered }
    var isFaceTime: Bool { type == 8 || type == 16 }
}

@MainActor
final class CallService: ObservableObject {
    static let shared = CallService()

    @Published private(set) var hasAccess = false
    @Published private(set) var recents: [CallRecord] = []

    private let path = NSHomeDirectory() + "/Library/Application Support/CallHistoryDB/CallHistory.storedata"
    private var db: SQLiteDB?
    private var lastID: Int64 = -1
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { CallService.shared.poll() }
        }
    }

    private func poll() {
        if db == nil { db = SQLiteDB(path: path) }
        guard let db else { hasAccess = false; return }
        var maxID: Int64 = 0
        let ok = db.query("SELECT IFNULL(MAX(Z_PK),0) FROM ZCALLRECORD") { maxID = $0.int(0) }
        hasAccess = ok
        guard ok else { self.db = nil; return }
        guard maxID != lastID else { return }
        let first = lastID < 0
        let prev = lastID
        lastID = maxID

        var list: [CallRecord] = []
        db.query("""
        SELECT Z_PK, IFNULL(ZADDRESS,''), ZDATE, IFNULL(ZDURATION,0), IFNULL(ZORIGINATED,0), IFNULL(ZANSWERED,0), IFNULL(ZCALLTYPE,1)
        FROM ZCALLRECORD ORDER BY ZDATE DESC LIMIT 30
        """) { r in
            list.append(CallRecord(id: r.int(0), address: r.text(1) ?? "",
                                   date: Date(timeIntervalSinceReferenceDate: r.double(2)),
                                   duration: r.double(3), outgoing: r.int(4) != 0,
                                   answered: r.int(5) != 0, type: Int(r.int(6))))
        }
        recents = list
        if !first, let newest = list.first(where: { $0.id > prev }), newest.missed {
            NotchViewModel.shared.showPeek(.call(title: ContactsService.shared.displayName(for: newest.address),
                                                 body: L("Missed call")), duration: 5)
        }
    }

    /// Starts a call through the paired iPhone (Continuity) or FaceTime.
    func call(_ number: String, faceTimeAudio: Bool = false) {
        let n = number.filter { $0.isNumber || $0 == "+" || $0 == "@" || $0 == "." || $0.isLetter }
        guard !n.isEmpty else { return }
        let scheme = faceTimeAudio ? "facetime-audio" : "tel"
        if let url = URL(string: "\(scheme)://\(n)") { NSWorkspace.shared.open(url) }
    }
}
