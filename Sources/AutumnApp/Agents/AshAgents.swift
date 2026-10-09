import Foundation
import SwiftUI
import AutumnServices

// LEATR project agents for Autumn iOS. Swift port of leatr-ash scripts/ash/{ash-shell64,ash-canvas,ash-agents}.js.
// Deterministic reflexes across Shell 64 (reflexive variable state, integers only). No outside AI, no network model calls.
// Reads the Shell 64 state + agents contract from the private leatr-ash repo via the admin's GitHub token; keeps optimized state locally on the device.

struct AshRec {
    var idx: Int
    var pre: String
    var k: String
    var bl: Int
    var rbli: Int
    var t: String
    var a: String
    var shell: String
    var rest: String
    var post: String

    var kind: String { bl == 0 ? "data" : (rbli >= 1 ? "buildable" : "sequence") }
    func line() -> String { "\(pre)k=\(k) bl=\(bl) rbli=\(rbli) t=\(t) a=\(a) shell=\(shell) \(rest)\(post)" }
}

struct AshShell64State {
    var lines: [String]
    var recs: [AshRec]

    static let pattern = try! NSRegularExpression(
        pattern: #"^(\s*irin \("Data: )k=(\S+) bl=(\d+) rbli=(\d+) t=(\S+) a=(\S+) shell=(\S+) (kind=[^"]*)("\)\s*)$"#)

    static func parse(_ text: String) -> AshShell64State {
        let lines = text.components(separatedBy: "\n")
        var recs: [AshRec] = []
        for (i, ln) in lines.enumerated() {
            let ns = ln as NSString
            guard let m = pattern.firstMatch(in: ln, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges == 10 else { continue }
            func g(_ n: Int) -> String { ns.substring(with: m.range(at: n)) }
            recs.append(AshRec(idx: i, pre: g(1), k: g(2), bl: Int(g(3)) ?? 0, rbli: Int(g(4)) ?? 0, t: g(5), a: g(6), shell: g(7), rest: g(8), post: g(9)))
        }
        return AshShell64State(lines: lines, recs: recs)
    }

    func serialize() -> String {
        var l = lines
        for r in recs { l[r.idx] = r.line() }
        return l.joined(separator: "\n")
    }

    func find(_ prefix: String) -> [Int] {
        recs.indices.filter { recs[$0].k.hasPrefix(prefix) }
    }
}

struct AshContract {
    var verb: [String: String] = [:]
    var shell: [String: String] = [:]
    var alias: [String: String] = [:]
    var defVerb = "build"

    static func parse(_ src: String) -> AshContract {
        var c = AshContract()
        let noComments = src.components(separatedBy: "\n").map { line -> String in
            if let r = line.range(of: "//") { return String(line[line.startIndex..<r.lowerBound]) }
            return line
        }.joined(separator: "\n")
        guard let re = try? NSRegularExpression(pattern: #"(\w+)\.([^\s=]+)=([^\s"]+)"#) else { return c }
        let ns = noComments as NSString
        for m in re.matches(in: noComments, range: NSRange(location: 0, length: ns.length)) {
            let a = ns.substring(with: m.range(at: 1)), b = ns.substring(with: m.range(at: 2)), v = ns.substring(with: m.range(at: 3))
            switch a {
            case "verb": c.verb[b] = v
            case "shell": c.shell[b] = v
            case "alias": c.alias[b] = v
            case "default": if b == "verb" { c.defVerb = v }
            default: break
            }
        }
        return c
    }
}

struct AshTask: Codable, Identifiable {
    var id: String
    var topic: String
    var domain: String
    var verb: String
    var tool: String
    var shell: String
    var status: String
    var hits: Int = 0
    var program: String = ""
    var emotion: String = "neutral"
}

struct AshProject: Codable {
    var project: String
    var goal: String
    var chiefEmotion: String
    var assistants: [String]
    var tasks: [AshTask]
    var updated: String
}

enum AshAgents {
    static func slug(_ s: String) -> String {
        let l = s.lowercased()
        var out = "", lastDash = false
        for ch in l.unicodeScalars {
            if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") { out.unicodeScalars.append(ch); lastDash = false }
            else if !lastDash { out += "-"; lastDash = true }
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "project" : out
    }

    static func words(_ text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"[a-z0-9+#]+"#) else { return [] }
        let l = text.lowercased() as NSString
        return re.matches(in: l as String, range: NSRange(location: 0, length: l.length)).map { l.substring(with: $0.range) }
    }

    static func normWord(_ w: String) -> String { w == "c#" ? "csharp" : w }

    static func topicOf(_ k: String) -> String { k.split(separator: "/", omittingEmptySubsequences: false).prefix(2).joined(separator: "/") }

    /// Topics ordered by maturity (buildable desc, sequence desc, name asc).
    static func harvestTopics(_ st: AshShell64State) -> [String] {
        var by: [String: (b: Int, s: Int)] = [:]
        for r in st.recs {
            let t = topicOf(r.k); var e = by[t] ?? (0, 0)
            if r.kind == "buildable" { e.b += 1 } else if r.kind == "sequence" { e.s += 1 }
            by[t] = e
        }
        return by.keys.sorted { a, b in
            let x = by[a]!, y = by[b]!
            if x.b != y.b { return x.b > y.b }
            if x.s != y.s { return x.s > y.s }
            return a < b
        }
    }

    static func topTopic(_ st: AshShell64State) -> String { harvestTopics(st).first ?? "syntax/ash" }

    static func plan(_ st: AshShell64State, _ c: AshContract, _ goal: String) -> [AshTask] {
        var topics = Set<String>(), order: [String] = [], verb: String? = nil
        for w in words(goal).map(normWord) {
            if verb == nil, c.verb[w] != nil { verb = w }
            if let a = c.alias[w], !topics.contains(a) { topics.insert(a); order.append(a) }
        }
        let v = verb ?? c.defVerb
        if order.isEmpty { order = [topTopic(st)] }
        return order.enumerated().map { (i, topic) in
            let domain = String(topic.split(separator: "/").first ?? "")
            return AshTask(id: "t\(i + 1):" + topic.replacingOccurrences(of: "/", with: "-"), topic: topic, domain: domain,
                           verb: v, tool: c.verb[v] ?? "Maze", shell: c.shell[domain] ?? "-", status: "planned")
        }
    }

    /// Manager: Ash Canvas reflex across the topic (route + optimize, depth capped at 7) then compose the Ash program.
    static func run(_ st: inout AshShell64State, _ task: AshTask) -> AshTask {
        var t = task
        let hits = st.find(task.topic + "/")
        for i in hits {
            let r = st.recs[i]
            let nbl = min(r.bl + 1, 7), nrbli = min(r.rbli + 1, 7)
            st.recs[i].bl = nbl; st.recs[i].rbli = nrbli
            st.recs[i].t = task.tool.isEmpty ? r.t : task.tool
            st.recs[i].shell = task.shell.isEmpty ? r.shell : task.shell
        }
        let top = st.find(task.topic + "/").sorted { a, b in
            let x = st.recs[a], y = st.recs[b]
            let sx = x.bl + x.rbli, sy = y.bl + y.rbli
            if sx != sy { return sx > sy }
            return x.k < y.k
        }.prefix(3)
        let name = "Task" + task.id.filter { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII }
        var L = ["(\(name)):-: {", "  {{env:\(task.domain)}} [[script:\(task.id)]]", "  var (s) // working slot", "  var (k) // Shell 64 key"]
        for (n, i) in top.enumerated() {
            let r = st.recs[i]
            L.append("  irin (\"Data: k=\(r.k)\")")
            L.append("  shell64.read (k) placeto (s)")
            L.append("  \(task.tool) [frp:\(task.shell == "-" ? "Geological" : task.shell)/\(task.tool)/R]")
            L.append("  irout (\"\(task.verb) \(n + 1): \"placeto (s))")
        }
        if top.isEmpty { L.append("  irout (\"No Shell 64 records for \(task.topic) yet: \"placeto (s))") }
        L.append("}|';'|")
        t.status = "done"; t.hits = hits.count; t.program = L.joined(separator: "\n"); t.emotion = hits.isEmpty ? "sad" : "happy"
        return t
    }

    static func respond(_ st: inout AshShell64State, _ c: AshContract, _ prompt: String, nowISO: String) -> AshProject {
        let tasks = plan(st, c, prompt)
        var done: [AshTask] = []
        for t in tasks { done.append(run(&st, t)) }
        var domains: [String] = []
        for t in done where !domains.contains(t.domain) { domains.append(t.domain) }
        return AshProject(project: slug(String(prompt.prefix(40))), goal: prompt,
                          chiefEmotion: done.contains { $0.emotion == "sad" } ? "sad" : "happy",
                          assistants: domains, tasks: done, updated: nowISO)
    }
}

@MainActor
final class AshAgentsModel: ObservableObject {
    struct Msg: Identifiable { let id = UUID(); let user: Bool; let text: String; let program: String? }
    @Published var msgs: [Msg] = [Msg(user: false, text: "Autumn here, team lead. Give me a goal; my assistant lead and team split it over Shell 64. Try \"create another team member to triangulate\". Runs on this device; no outside AI.", program: nil)]
    @Published var busy = false
    @Published var status = "Shell 64: not loaded"

    private var state: AshShell64State?
    private var team: AshTeamState?
    private var relayTeam: Data?   // public mode: team state held on this device, sent back to the read-only relay each time
    private var teamParams = TeamParams()
    private var contract = AshContract()
    // leatr-ash is a private repo: raw.githubusercontent.com always 404s, so read through the authenticated Contents API
    // (the admin's own GitHub sign-in token, same as the Training catalogs). Live state first, then the condensed seed.
    private let statePaths = ["ashtree/shell64/state.ash", "Training/shell64/shell64.state.ash"]
    private let contractPath = "scripts/ash/agents.ash"

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ashagents", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func fetch(_ paths: [String], cache: String) async -> String? {
        let f = dir.appendingPathComponent(cache + ".seed")
        for path in paths {
            if let file = try? await GitHubClient.shared.readFile(owner: "DART-Skyboard", repo: "leatr-ash", path: path, ref: "main"),
               let s = file.decodedContent, !s.isEmpty {
                try? s.write(to: f, atomically: true, encoding: .utf8); return s
            }
        }
        return try? String(contentsOf: f, encoding: .utf8)
    }

    func load(reset: Bool = false) async {
        if state != nil && !reset { return }
        let local = dir.appendingPathComponent("shell64.state.ash")
        if !reset, let t = try? String(contentsOf: local, encoding: .utf8) { state = AshShell64State.parse(t) }
        else if let t = await fetch(statePaths, cache: "shell64") { state = AshShell64State.parse(t); try? t.write(to: local, atomically: true, encoding: .utf8) }
        if let c = await fetch([contractPath], cache: "agents") { contract = AshContract.parse(c); teamParams = TeamParams.parse(c) }
        status = state.map { "Shell 64: \($0.recs.count) records" } ?? "Shell 64 unavailable (offline, no cache)"
    }

    /// One brain, two windows: the main chat and this console call the same `answer`, share the team state and one history.
    static let shared = AshAgentsModel()
    static let commandRE = try! NSRegularExpression(pattern: #"\b(create|add|spawn|assign|remove|study|have)\b[^.?!]*\b(team ?members?|agents?|managers?|assistant ?chiefs?|chief)\b|^\s*/?(agents?|team|goal)\b[:\s]|\bteam lead\b|\bshell ?64 team\b"#, options: [.caseInsensitive])
    /// True when a main-chat message is an agent / team command or a Tool Radian request.
    static func isCommand(_ text: String) -> Bool {
        if AshRadian.respond(text, ctx: AshRadian.live) != nil { return true }
        return commandRE.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
    /// Main-chat exchanges are mirrored into the console history.
    func record(_ user: String, _ reply: (text: String, program: String?)) {
        msgs.append(Msg(user: true, text: user, program: nil)); msgs.append(Msg(user: false, text: reply.text, program: reply.program))
    }

    func send(_ text: String) {
        let goal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, !busy else { return }
        msgs.append(Msg(user: true, text: goal, program: nil))
        busy = true
        Task {
            let r = await answer(goal)
            msgs.append(Msg(user: false, text: r.text, program: r.program)); busy = false
        }
    }

    func answer(_ goal: String) async -> (text: String, program: String?) {
        // Tool Radian (encode / decode / analyze / bare math) answers on this device: nothing is sent or learned.
        if let r = AshRadian.respond(goal, ctx: AshRadian.live) { return (r, nil) }
        // Admin (token that can read leatr-ash): direct path below. Everyone else: the read-only Shell 64 door in the Apps Script.
        if await GitHubClient.shared.hasToken() { await load() }
        if state == nil {
            do {
                let r = try await AutumnTeamRelay.ask(goal, team: relayTeam)
                relayTeam = r.team
                status = "Autumn's knowledge base (read-only; your data stays on your device)"
                return (r.text, r.program)
            } catch { return ("Autumn's knowledge base is not reachable right now. Try again in a moment.", nil) }
        }
        guard var st = state else { return ("Shell 64 is not available yet. Try again in a moment.", nil) }
        let now = ISO8601DateFormatter().string(from: Date())
        let t = AshTeam.handle(&st, contract, teamParams, team: team, text: goal, now: now)
        team = t; state = st
        try? st.serialize().write(to: dir.appendingPathComponent("shell64.state.ash"), atomically: true, encoding: .utf8)
        if let data = try? JSONEncoder().encode(t) { try? data.write(to: dir.appendingPathComponent("team-\(t.project).json")) }
        status = "Shell 64: \(st.recs.count) records (optimized on device)"
        return (AshTeam.report(t), AshTeam.program(t))
    }
}

struct AgentsConsoleView: View {
    @ObservedObject private var model = AshAgentsModel.shared
    @State private var input = ""
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        let chrome = themeVM.chrome
        VStack(spacing: 0) {
            Text("AGENTS · Autumn (Team Lead) / Assistant Lead / Team")
                .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(chrome.accent)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.msgs) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.text).font(.system(size: 11, design: .monospaced)).foregroundColor(m.user ? .white : Color(hex: "#9cdcfe"))
                            if let p = m.program { DisclosureGroup("Ash program") { Text(p).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.7)) }
                                .font(.system(size: 10, design: .monospaced)) }
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(m.user ? chrome.accent.opacity(0.12) : Color.white.opacity(0.06)))
                    }
                }.padding(.horizontal, 10)
            }
            Text(model.status).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4)).padding(.top, 4)
            HStack {
                TextField("e.g. analyze python grammar", text: $input).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                    .onSubmit { model.send(input); input = "" }
                Button("SEND") { model.send(input); input = "" }.font(.system(size: 11, weight: .bold, design: .monospaced)).disabled(model.busy)
            }.padding(10)
        }
        .task { if await GitHubClient.shared.hasToken() { await model.load() } }
    }
}

/// Public AGENTS overlay (every user): Autumn leads a team over her knowledge base; read-only, nothing you say is learned.
struct AgentsOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation

    var body: some View {
        let chrome = themeVM.chrome
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { appNav.showAgents = false }
            VStack(spacing: 0) {
                HStack {
                    Text("AGENTS").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(chrome.accent)
                    Spacer()
                    Button("✕") { appNav.showAgents = false }.foregroundColor(.white.opacity(0.6))
                }.padding(12)
                AgentsConsoleView()
            }
            .frame(width: min(380, AppGeometry.bounds.width - 24), height: min(600, AppGeometry.bounds.height * 0.75))
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(chrome.accent.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
    }
}
