import AppKit
import SQLite3
import ApplicationServices

/// Localized string: the key is the English text; translations live in <lang>.lproj/Localizable.strings.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

/// Diagnostic log, compiled only into debug builds (`swift build`); release builds stay silent.
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("[YANA] %@", message())
    #endif
}

enum AppleScript {
    /// Serial queue for every AppleScript: Apple events can take hundreds of ms (or time out when the
    /// target app hangs), so they never run on the main thread. Serial = commands keep their order.
    static let queue = DispatchQueue(label: "com.yana.applescript", qos: .userInitiated)

    /// Runs synchronously on the calling thread: call it only from `AppleScript.queue`.
    @discardableResult
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { debugLog("AppleScript error: \(error)") }
        return result
    }
    /// Fire-and-forget script on `AppleScript.queue`.
    static func runAsync(_ source: String) {
        queue.async { run(source) }
    }
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    static var fullDisk: Bool {
        // A real open() is needed: access()/isReadableFile don't reflect TCC. Close the descriptor right away.
        let fd = open(NSHomeDirectory() + "/Library/Messages/chat.db", O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }
    static func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum MediaKey: Int32 { case playPause = 16, next = 17, previous = 18 }

enum SystemInput {
    /// Sends a hardware media key (works with any app: browsers, VLC, Podcasts...). Needs Accessibility.
    static func send(_ key: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func keystroke(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static func shell(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }
}

final class SQLiteDB {
    private var db: OpaquePointer?

    init?(path: String) {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 500)
    }
    deinit { sqlite3_close(db) }

    struct Row {
        let stmt: OpaquePointer?
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func text(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        func blob(_ i: Int32) -> Data? {
            guard let p = sqlite3_column_blob(stmt, i) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
        }
    }

    @discardableResult
    func query(_ sql: String, _ each: (Row) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { each(Row(stmt: stmt)) }
        return true
    }
}

extension Date {
    var shortRelative: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(self) { f.timeStyle = .short }
        else if cal.isDateInYesterday(self) { return L("Yesterday") }
        else if let d = cal.dateComponents([.day], from: self, to: Date()).day, d < 7 { f.setLocalizedDateFormatFromTemplate("EEE") }
        else { f.setLocalizedDateFormatFromTemplate("dMM") }
        return f.string(from: self)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}
