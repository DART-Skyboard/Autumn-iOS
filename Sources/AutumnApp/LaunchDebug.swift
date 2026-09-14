import Foundation

/// TF96 diagnostic only — narrows down the scene-create watchdog hang (builds 91-95,
/// ~20s CPU burned in a SwiftUI body/AttributeGraph cycle, see README Build 96) without
/// needing Xcode/dSYM symbolication, which isn't available in this iPhone-only workflow.
///
/// `mark(_:)` appends a timestamped label to a UserDefaults-backed trace and writes
/// through immediately (UserDefaults is backed by a plist on disk and is safe to read
/// on the next process launch even if this one gets SIGKILLed mid-hang — unlike an
/// in-memory log or a `print()`/os_log line, which the watchdog kill takes with it and
/// which isn't visible in the .ips crash report either).
///
/// On the NEXT app launch, `snapshotAndReset()` moves whatever trace exists (from the
/// previous, possibly-killed session) into `lastSessionTrace`, then clears the live
/// trace so this session starts clean. `AutumnApp` surfaces `lastSessionTrace` as a
/// small on-screen readout — if last time hung after only 2-3 marks, that's our view;
/// if it shows the SAME mark repeated dozens/hundreds of times, that view's body is
/// looping and that's the actual bug (see the `@Published`-during-body-eval frame in
/// the build-95 crash log).
enum LaunchDebug {
    private static let liveKey = "_launchDebugTraceLive"
    private static let lastKey = "_launchDebugTraceLast"
    private static let maxEntries = 400

    /// Call once, as the very first thing in AutumnApp.init() — before any other mark.
    static func snapshotAndReset() {
        let d = UserDefaults.standard
        if let previous = d.array(forKey: liveKey) as? [String] {
            d.set(previous, forKey: lastKey)
        }
        d.set([String](), forKey: liveKey)
    }

    /// Append a checkpoint. `.set()` here is an in-memory cache update — UserDefaults
    /// batches the actual disk/XPC write-back on its own schedule, which is virtually
    /// instant. `.synchronize()` (removed here — TF99) is what made this NOT safe to
    /// call from a View's `body`: it forces a synchronous wait for a reply from another
    /// process (cfprefsd) on every call. That's exactly what the build 98 crash log
    /// showed — `NSUserDefaults setObject:forKey:` blocked on
    /// `xpc_connection_send_message_with_reply_sync`, called directly from inside a
    /// SwiftUI body evaluation. SwiftUI can invoke `body` many times during normal
    /// layout settling; each call paying a blocking IPC round-trip is more than enough
    /// on its own to trip the 10-20s scene-create watchdog. This diagnostic tool was
    /// masking (or possibly *was*) the very hang it was added to find.
    static func mark(_ label: String) {
        let d = UserDefaults.standard
        var trace = (d.array(forKey: liveKey) as? [String]) ?? []
        let ts = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        trace.append("\(ts)  \(label)")
        if trace.count > maxEntries {
            // Keep it bounded even if something is genuinely looping hundreds of times
            // a second — cap to the most recent window so the tail (where it eventually
            // got killed) is what's preserved, not the start.
            trace.removeFirst(trace.count - maxEntries)
        }
        d.set(trace, forKey: liveKey)
    }

    /// The previous session's trace (captured by `snapshotAndReset()` at this
    /// session's start) — this is what actually tells us how far last launch got.
    static var lastSessionTrace: [String] {
        (UserDefaults.standard.array(forKey: lastKey) as? [String]) ?? []
    }

    /// Compact one-line summary for an on-screen readout: last few marks, plus a count
    /// of the most-repeated label (the tell for a body stuck in a re-render loop).
    static var lastSessionSummary: String {
        let trace = lastSessionTrace
        guard !trace.isEmpty else { return "no previous trace" }
        let labels = trace.map { line -> String in
            guard let range = line.range(of: "  ") else { return line }
            return String(line[range.upperBound...])
        }
        let counts = Dictionary(grouping: labels, by: { $0 }).mapValues(\.count)
        let top = counts.max(by: { $0.value < $1.value })
        let tail = trace.suffix(3).joined(separator: " | ")
        if let top, top.value > 5 {
            return "\(trace.count) marks · looping: \(top.key) ×\(top.value) · tail: \(tail)"
        }
        return "\(trace.count) marks · tail: \(tail)"
    }
}
