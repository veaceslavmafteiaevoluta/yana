import EventKit
import AppKit

struct CalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: NSColor
    let location: String?
    let joinURL: URL?
    var service: String? {
        guard let h = joinURL?.host?.lowercased() else { return nil }
        if h.contains("zoom") { return "Zoom" }
        if h.contains("meet.google") { return "Meet" }
        if h.contains("teams") { return "Teams" }
        if h.contains("webex") { return "Webex" }
        return "Link"
    }
}

private func meetingURL(_ e: EKEvent) -> URL? {
    let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]
    func match(_ u: URL) -> Bool { hosts.contains { u.host?.lowercased().hasSuffix($0) == true } }
    if let u = e.url, match(u) { return u }
    let text = [e.location, e.notes].compactMap { $0 }.joined(separator: "\n")
    guard !text.isEmpty, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    return det.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first(where: match)
}

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var authorized = false

    private let store = EKEventStore()
    private var notified = Set<String>()
    private var timer: Timer?

    func start() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.reload() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { CalendarService.shared.reload() }
        }
        if authorized { reload() } else { requestAccess() }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    CalendarService.shared.authorized = granted
                    CalendarService.shared.reload()
                }
            }
        }
    }

    func reload() {
        guard authorized else { return }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: pred)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { CalEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? L("Event"),
                            start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay,
                            color: $0.calendar?.color ?? .systemBlue, location: $0.location, joinURL: meetingURL($0)) }

        for e in events where !e.allDay {
            let mins = e.start.timeIntervalSince(now) / 60
            if mins > 0, mins <= 10, !notified.contains(e.id) {
                notified.insert(e.id)
                NotchViewModel.shared.showPeek(.event(title: e.title, body: L("In %ld min", Int(mins.rounded())) + (e.location.map { " · \($0)" } ?? "")), duration: 5)
            }
        }
    }

    func join(_ e: CalEvent) { if let u = e.joinURL { NSWorkspace.shared.open(u) } }

    func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}
