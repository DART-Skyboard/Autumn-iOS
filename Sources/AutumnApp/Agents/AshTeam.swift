import Foundation

// Swift port of leatr-ash scripts/ash/ash-team.js: Autumn (Team Lead) + Assistant Lead + team members.
// Members triangulate (each step they see every other member's task), retarget on overlap/starvation, co-work on user-pinned
// shared topics, and the Assistant Lead spawns members for backlog. Deterministic; no outside AI.

struct TeamTask: Codable {
    var topic: String
    var domain: String
    var verb: String
    var tool: String
    var shell: String
    var status: String = "working"
    var hits: Int = 0
    var step: Int = 0
    var emotion: String = "neutral"
}

struct TeamMember: Codable, Identifiable {
    var id: String
    var name: String
    var role: String            // Worker | Triangulator | AssistantLead
    var pinned: Bool
    var task: TeamTask?
    var touched: [String] = []
    var watching: [String] = []
}

struct TeamEvent: Codable { var r: Int; var who: String; var what: String }
struct TeamQueueItem: Codable { var topic: String; var verb: String }

struct AshTeamState: Codable {
    var project: String
    var goal: String
    var lead = "Autumn"
    var members: [TeamMember] = []
    var queue: [TeamQueueItem] = []
    var log: [TeamEvent] = []
    var round = 0
    var seq = 0
    var complete = false
    var chiefEmotion = "neutral"
    var updated = ""
}

struct TeamParams {
    var lead = "Autumn", maxMembers = 8, rounds = 6, stepsPerTask = 3
    static func parse(_ src: String) -> TeamParams {
        var p = TeamParams()
        guard let re = try? NSRegularExpression(pattern: #"team\.(\w+)=([^\s"]+)"#) else { return p }
        let ns = src as NSString
        for m in re.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            let k = ns.substring(with: m.range(at: 1)), v = ns.substring(with: m.range(at: 2))
            switch k {
            case "lead": p.lead = v
            case "maxMembers": p.maxMembers = Int(v) ?? p.maxMembers
            case "rounds": p.rounds = Int(v) ?? p.rounds
            case "stepsPerTask": p.stepsPerTask = Int(v) ?? p.stepsPerTask
            default: break
            }
        }
        return p
    }
}

enum AshTeam {
    static func rx(_ pat: String, _ s: String) -> Bool { s.range(of: pat, options: .regularExpression) != nil }

    static func note(_ t: inout AshTeamState, _ who: String, _ what: String) {
        t.log.append(TeamEvent(r: t.round, who: who, what: what)); if t.log.count > 200 { t.log.removeFirst() }
    }

    static func workers(_ t: AshTeamState) -> [Int] { t.members.indices.filter { t.members[$0].role == "Worker" } }
    static func active(_ t: AshTeamState) -> [Int] { workers(t).filter { t.members[$0].task != nil && t.members[$0].task!.status != "done" } }

    @discardableResult
    static func spawn(_ t: inout AshTeamState, role: String, task: TeamTask?, why: String, pinned: Bool = false) -> Int {
        t.seq += 1; let n = t.seq
        let pre = role == "AssistantLead" ? "al" : role == "Triangulator" ? "tri" : "m"
        let nm = (role == "AssistantLead" ? "Assistant Lead " : role == "Triangulator" ? "Triangulator " : "Member ") + "\(n)"
        t.members.append(TeamMember(id: pre + "\(n)", name: nm, role: role, pinned: pinned, task: task))
        note(&t, pre + "\(n)", "joined as \(role)" + (task.map { " on \($0.topic)" } ?? "") + (why.isEmpty ? "" : " (\(why))"))
        return t.members.count - 1
    }

    static func mkTask(_ c: AshContract, _ topic: String, _ verb: String?) -> TeamTask {
        let domain = String(topic.split(separator: "/").first ?? ""), v = verb ?? c.defVerb
        return TeamTask(topic: topic, domain: domain, verb: v, tool: c.verb[v] ?? "Maze", shell: c.shell[domain] ?? "-")
    }

    static func nextTopic(_ st: AshShell64State, _ t: AshTeamState, except: Int?, avoid: Set<String> = []) -> String? {
        var taken = Set<String>()
        for i in active(t) where i != except { taken.insert(t.members[i].task!.topic) }
        return AshAgents.harvestTopics(st).first { !taken.contains($0) && !avoid.contains($0) }
    }

    static func open(_ st: AshShell64State, _ c: AshContract, _ tp: TeamParams, goal: String, now: String) -> AshTeamState {
        var t = AshTeamState(project: AshAgents.slug(String(goal.prefix(40))), goal: goal, lead: tp.lead)
        spawn(&t, role: "AssistantLead", task: nil, why: "Autumn delegates monitoring")
        for pt in AshAgents.plan(st, c, goal) {
            if workers(t).count < tp.maxMembers - 2 { spawn(&t, role: "Worker", task: mkTask(c, pt.topic, pt.verb), why: "planned from goal") }
            else { t.queue.append(TeamQueueItem(topic: pt.topic, verb: pt.verb)) }
        }
        note(&t, "lead", "Autumn opened \"\(goal)\" with \(workers(t).count) member(s)")
        t.updated = now
        return t
    }

    /// nil when the text is not a team command. "status" returns .status.
    enum Cmd { case status, spawned, full, empty }
    static func command(_ st: AshShell64State, _ c: AshContract, _ tp: TeamParams, _ t: inout AshTeamState, _ text: String, now: String) -> Cmd? {
        let l = text.lowercased()
        let isNew = rx(#"\b(create|add|make|spawn|bring|new|another|more)\b"#, l)
        let who = rx(#"\b(team ?members?|members?|agents?|teammates?|helpers?|assistants?|leads?)\b"#, l)
        if rx(#"\b(status|report|board|who is|who's|progress)\b"#, l) && !isNew { return .status }
        guard isNew && who else { return nil }
        if t.members.count >= tp.maxMembers { note(&t, "lead", "team is full (\(tp.maxMembers))"); return .full }
        let role = rx(#"\bassistant\s+leads?\b"#, l) ? "AssistantLead" : rx(#"triangulat|monitor|watch|cross-?check|oversee"#, l) ? "Triangulator" : "Worker"
        var topic: String? = nil, verb: String? = nil
        for w0 in AshAgents.words(l) {
            let w = w0 == "c#" ? "csharp" : w0
            if verb == nil, c.verb[w] != nil { verb = w }
            if topic == nil, let a = c.alias[w] { topic = a }
        }
        if role == "Worker" {
            let pinned = topic != nil
            if topic == nil { topic = t.queue.isEmpty ? nextTopic(st, t, except: nil) : t.queue.removeFirst().topic }
            guard let tp2 = topic else { note(&t, "lead", "nothing left to assign"); return .empty }
            spawn(&t, role: "Worker", task: mkTask(c, tp2, verb), why: pinned ? "asked by user" : "unclaimed topic", pinned: pinned)
        } else { spawn(&t, role: role, task: nil, why: "asked by user") }
        t.updated = now
        return .spawned
    }

    static func recsFor(_ st: AshShell64State, _ topic: String) -> [Int] {
        st.find(topic + "/").sorted { a, b in
            let x = st.recs[a], y = st.recs[b], sx = x.bl + x.rbli, sy = y.bl + y.rbli
            return sx != sy ? sx > sy : x.k < y.k
        }
    }

    static func tick(_ st: inout AshShell64State, _ c: AshContract, _ tp: TeamParams, _ t: inout AshTeamState, now: String) {
        t.round += 1
        var fin = 0
        let snapIds = t.members.map { $0.id }
        let monitor = t.members.first { $0.role == "Triangulator" }?.id ?? t.members.first { $0.role == "AssistantLead" }?.id
        let beforeWorking = t.members.filter { $0.task?.status == "working" }.count
        for (idx, mi) in workers(t).enumerated() {
            t.members[mi].watching = snapIds.filter { $0 != t.members[mi].id }
            guard var task = t.members[mi].task, task.status != "done" else { continue }
            let wl = workers(t)
            let peers = active(t).filter { $0 != mi && t.members[$0].task!.topic == task.topic }
            if !peers.isEmpty && !t.members[mi].pinned && peers.contains(where: { (wl.firstIndex(of: $0) ?? 0) < idx }) {
                if let nt = nextTopic(st, t, except: mi) {
                    note(&t, monitor ?? "lead", "\(t.members[mi].id) overlaps \(task.topic) -> retarget to \(nt)")
                    task = mkTask(c, nt, task.verb); t.members[mi].touched = []
                }
            }
            var recs = recsFor(st, task.topic)
            if recs.isEmpty {
                if let alt = nextTopic(st, t, except: mi, avoid: [task.topic]) {
                    note(&t, t.members[mi].id, "\(task.topic) has no records -> switch to \(alt)")
                    task = mkTask(c, alt, task.verb); t.members[mi].touched = []; recs = recsFor(st, alt)
                } else {
                    task.status = "done"; fin += 1; task.emotion = "sad"; t.members[mi].task = task
                    note(&t, t.members[mi].id, "no Shell 64 records for \(task.topic)"); continue
                }
            }
            t.members[mi].task = task
            let co = active(t).filter { t.members[$0].task!.topic == task.topic }
            let pos = co.firstIndex(of: mi) ?? 0
            let ri = recs[(task.step * co.count + pos) % recs.count]
            let key = st.recs[ri].k
            if !t.members[mi].touched.contains(key) {
                // Ash Canvas reflex on this one record: route (bl+1, rbli+1), depth capped at 7
                st.recs[ri].bl = min(st.recs[ri].bl + 1, 7); st.recs[ri].rbli = min(st.recs[ri].rbli + 1, 7)
                st.recs[ri].t = task.tool; st.recs[ri].shell = task.shell
                t.members[mi].touched.append(key); task.hits += 1
            }
            task.step += 1
            if co.count > 1 && task.step == 1 { note(&t, t.members[mi].id, "co-working \(task.topic) with \(co.count - 1) other(s)") }
            if task.step >= tp.stepsPerTask {
                task.status = "done"; fin += 1; task.emotion = task.hits > 0 ? "happy" : "sad"
                note(&t, t.members[mi].id, "finished \(task.topic) (\(task.hits) hits)")
            }
            t.members[mi].task = task
        }
        var idle = workers(t).filter { t.members[$0].task?.status == "done" }
        while !t.queue.isEmpty && !idle.isEmpty {
            let q = t.queue.removeFirst(), w = idle.removeFirst()
            t.members[w].task = mkTask(c, q.topic, q.verb); t.members[w].touched = []
            note(&t, t.members[w].id, "picked up \(q.topic) from backlog")
        }
        if !t.queue.isEmpty && t.members.count < tp.maxMembers {
            let q = t.queue.removeFirst()
            spawn(&t, role: "Worker", task: mkTask(c, q.topic, q.verb), why: "Assistant Lead saw backlog")
        }
        let lw = active(t).count
        if t.round > 1 && lw != beforeWorking - fin { note(&t, "assist", "lead sees \(lw) working, board had \(beforeWorking) -> re-synced") }
        t.updated = now
    }

    static func run(_ st: inout AshShell64State, _ c: AshContract, _ tp: TeamParams, _ t: inout AshTeamState, now: String) {
        var i = 0
        while i < tp.rounds && (!active(t).isEmpty || !t.queue.isEmpty) { tick(&st, c, tp, &t, now: now); i += 1 }
        let done = workers(t).allSatisfy { t.members[$0].task == nil || t.members[$0].task!.status == "done" }
        t.chiefEmotion = workers(t).contains { t.members[$0].task?.emotion == "sad" } ? "sad" : "happy"
        t.complete = done && t.queue.isEmpty
    }

    static func program(_ t: AshTeamState) -> String {
        var L: [String] = []
        for mi in workers(t) {
            let m = t.members[mi]; guard let task = m.task else { continue }
            L += ["(Member\(m.id)):-: {", "  {{env:\(task.domain)}} [[script:\(m.id)]]", "  var (s) // working slot", "  var (k) // Shell 64 key"]
            for (i, k) in m.touched.enumerated() {
                L += ["  irin (\"Data: k=\(k)\")", "  shell64.read (k) placeto (s)",
                      "  \(task.tool) [frp:\(task.shell == "-" ? "Geological" : task.shell)/\(task.tool)/R]",
                      "  irout (\"\(task.verb) \(i + 1): \"placeto (s))"]
            }
            if m.touched.isEmpty { L.append("  irout (\"No Shell 64 records for \(task.topic) yet: \"placeto (s))") }
            L.append("}|';'|")
        }
        return L.joined(separator: "\n")
    }

    static func report(_ t: AshTeamState) -> String {
        var l = ["Team \(t.project) — Lead \(t.lead), round \(t.round)" + (t.complete ? " (complete)" : "")]
        for m in t.members {
            if let k = m.task { l.append("• \(m.name) [\(m.role)] \(k.topic) \(k.status) \(k.step)/3 hits=\(k.hits)") }
            else { l.append("• \(m.name) [\(m.role)] watching \(m.watching.isEmpty ? "all" : "\(m.watching.count)")") }
        }
        if !t.queue.isEmpty { l.append("Backlog: " + t.queue.map { $0.topic }.joined(separator: ", ")) }
        let ev = t.log.suffix(6).map { "  r\($0.r) \($0.who): \($0.what)" }
        if !ev.isEmpty { l.append("Recent:"); l += ev }
        return l.joined(separator: "\n")
    }

    /// Chat entry point: a new goal opens a team; team commands grow it; "status" reports.
    static func handle(_ st: inout AshShell64State, _ c: AshContract, _ tp: TeamParams, team: AshTeamState?, text: String, now: String) -> AshTeamState {
        if var t = team, let cmd = command(st, c, tp, &t, text, now: now) {
            if case .status = cmd { return t }
            run(&st, c, tp, &t, now: now); return t
        }
        var t = open(st, c, tp, goal: text, now: now)
        run(&st, c, tp, &t, now: now)
        return t
    }
}
