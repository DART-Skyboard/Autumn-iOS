import Foundation
import LEATRCore
import AutumnServices

/// TF157: real, persistent analytics collection for the export system —
/// listens to the same ReflexActivityBus events LeatrMindMapScene already
/// visualizes, and additionally logs each one to a daily file
/// (ashtree/analytics/{yyyy-MM-dd}.json) via the existing GAS ashwrite
/// append path (the same mechanism journal/study-queue/ash-star already
/// use). One file per day keeps a date-range export from ever needing to
/// pull one giant ever-growing file — it only fetches the days actually
/// in range.
public final class AnalyticsEventLogger {
    public static let shared = AnalyticsEventLogger()
    private var observers: [NSObjectProtocol] = []
    private var sessionEvents: [AnalyticsEvent] = []
    private let sessionStart = Date()

    private init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ReflexActivityBus.notificationName, object: nil, queue: nil) { [weak self] note in
            guard let stage = note.userInfo?["stage"] as? String else { return }
            self?.record(category: "stage", label: stage)
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.toolNotificationName, object: nil, queue: nil) { [weak self] note in
            guard let tool = note.userInfo?["tool"] as? String else { return }
            let shell = (note.userInfo?["shell"] as? Int).flatMap { BRPNShell(rawValue: $0) }
            self?.record(category: "tool", label: tool, detail: shell?.displayName)
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.mathOpNotificationName, object: nil, queue: nil) { [weak self] note in
            guard let op = note.userInfo?["op"] as? String else { return }
            self?.record(category: "math", label: op)
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.emotionNotificationName, object: nil, queue: nil) { [weak self] note in
            guard let emotion = note.userInfo?["emotion"] as? String else { return }
            self?.record(category: "emotion", label: emotion)
        })
        // TF160: the three live real-time feeds (aircraft/satellite/vessel)
        // and presence — previously had no path into analytics logging at
        // all. "kind" carries which feed (aircraft/satellite/vessel);
        // label is the count actually injected, matching the same
        // category/label shape everything else here already uses so the
        // export's grouping logic doesn't need a special case for these.
        observers.append(nc.addObserver(forName: ReflexActivityBus.realTimeFeedNotificationName, object: nil, queue: nil) { [weak self] note in
            guard let kind = note.userInfo?["kind"] as? String, let count = note.userInfo?["count"] as? Int else { return }
            self?.record(category: "realtime_feed", label: kind, detail: "\(count)")
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.presenceNotificationName, object: nil, queue: nil) { [weak self] note in
            guard let count = note.userInfo?["connectedCount"] as? Int else { return }
            self?.record(category: "presence", label: "connected_users", detail: "\(count)")
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    private func record(category: String, label: String, detail: String? = nil) {
        let event = AnalyticsEvent(ts: Date(), category: category, label: label, detail: detail)
        sessionEvents.append(event)
        let day = Self.dayKey(for: event.ts)
        Task.detached(priority: .background) {
            _ = await AutumnGASClient.shared.ashwrite(
                path: "ashtree/analytics/\(day).json",
                uid: "analytics",
                append: true,
                payload: event.asDict
            )
        }
    }

    /// Every event recorded since this process launched — used for a
    /// "this session" export without any network round-trip, since it's
    /// already in memory.
    public func eventsThisSession() -> [AnalyticsEvent] { sessionEvents }

    /// Fetches every day's file in the given (inclusive) range from the
    /// repo directly — a session-only export never needs this, but a
    /// date-range export does, since sessionEvents only covers the
    /// current process's lifetime.
    public func fetchRange(from startDay: Date, to endDay: Date) async -> [AnalyticsEvent] {
        var out: [AnalyticsEvent] = []
        var cursor = Calendar.current.startOfDay(for: startDay)
        let end = Calendar.current.startOfDay(for: endDay)
        var daysChecked = 0
        while cursor <= end && daysChecked < 366 {
            let day = Self.dayKey(for: cursor)
            if let events = await fetchDay(day) { out.append(contentsOf: events) }
            cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            daysChecked += 1
        }
        return out.sorted { $0.ts < $1.ts }
    }

    private func fetchDay(_ day: String) async -> [AnalyticsEvent]? {
        let url = URL(string: "https://raw.githubusercontent.com/DART-Skyboard/leatr-ash/main/ashtree/analytics/\(day).json")!
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return arr.compactMap { AnalyticsEvent(dict: $0) }
    }

    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

public struct AnalyticsEvent {
    public let ts: Date
    public let category: String   // "stage" | "tool" | "math" | "emotion"
    public let label: String
    public let detail: String?

    var asDict: [String: Any] {
        var d: [String: Any] = ["ts": ISO8601DateFormatter().string(from: ts), "category": category, "label": label]
        if let detail { d["detail"] = detail }
        return d
    }

    init(ts: Date, category: String, label: String, detail: String?) {
        self.ts = ts; self.category = category; self.label = label; self.detail = detail
    }

    init?(dict: [String: Any]) {
        guard let tsStr = dict["ts"] as? String,
              let ts = ISO8601DateFormatter().date(from: tsStr),
              let category = dict["category"] as? String,
              let label = dict["label"] as? String
        else { return nil }
        self.ts = ts; self.category = category; self.label = label
        self.detail = dict["detail"] as? String
    }
}
