import SwiftUI
import LEATRCore
import AutumnServices

/// Movement Conjecture EOD — stockphonic / eodpropg / geopropg from movement-conjecture.html.
struct MovementConjectureView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var vm = MovementViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("MOVEMENT CONJECTURE EOD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.55))
                Text("Arc Edge finite dynamics. Personal conjecture engine — not a financial model. DOC replaces π. C = √(d × DOC)² with DOC = \(LEATRIdentity.DOC).")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.75))

                HStack {
                    labeledField("YR START", $vm.yearStart)
                    labeledField("YR END", $vm.yearEnd)
                    labeledField("EOD", $vm.eod)
                }

                ForEach($vm.slots) { $slot in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("TICKER", text: $slot.ticker)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .textInputAutocapitalization(.characters)
                                .padding(8).background(themeVM.chrome.surface).cornerRadius(4)
                            TextField("σ", text: $slot.sigmaText)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .keyboardType(.decimalPad)
                                .frame(width: 72)
                                .padding(8).background(themeVM.chrome.surface).cornerRadius(4)
                            Button("⬇") { Task { await vm.fetch(slot.id) } }
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(themeVM.chrome.accent)
                        }
                        HStack {
                            Text(slot.price.map { String(format: "$%.2f", $0) } ?? "NO QUOTE")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(slot.live ? Color(hex: "#00ff88") : .white.opacity(0.45))
                            Spacer()
                            if let r = slot.result {
                                Text("MSP \(r.fmtA)  DLSS \(r.fmtDlss)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(themeVM.chrome.accent)
                            }
                        }
                    }
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(themeVM.chrome.accent.opacity(0.18), lineWidth: 1))
                }

                HStack(spacing: 8) {
                    Button("▶ COMPUTE CONJECTURE") { vm.compute() }
                    Button("⬇ FETCH ALL") { Task { await vm.fetchAll() } }
                    Button("↺ RESET") { vm.reset() }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)

                HStack {
                    Button("+ ADD") { vm.addSlot() }
                    Button("− REMOVE") { vm.removeSlot() }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))

                if !vm.trajectory.isEmpty {
                    Text("TRAJECTORY \(vm.yearStart)—\(vm.yearEnd)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.chrome.accent.opacity(0.6))
                    MovementChart(points: vm.trajectory)
                        .frame(height: 140)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                }

                if let r = vm.lastResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESULTS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent.opacity(0.5))
                        row("C (radc²)", r.fmtC)
                        row("A √(c/s)", r.fmtA)
                        row("DX", r.fmtDx)
                        row("DLSS", r.fmtDlss)
                        row("MFMSP", r.fmtMfmsp)
                        row("SPNCRYNODE", r.fmtNode)
                        row("DOC CIRC d=10", String(format: "%.4f", LEATRIdentity.arcEdgeCircumference(diameter: 10)))
                    }
                }

                Text(vm.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(16)
        }
    }

    private func labeledField(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            TextField(label, text: text)
                .textFieldStyle(.plain).foregroundColor(.white)
                .keyboardType(.numbersAndPunctuation)
                .padding(8).background(themeVM.chrome.surface).cornerRadius(4)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.85))
        }
    }
}

struct MovementChart: View {
    var points: [Double]
    var body: some View {
        Canvas { ctx, size in
            guard points.count > 1 else { return }
            let mn = points.min() ?? 0
            let mx = points.max() ?? 1
            let span = max(mx - mn, 1e-9)
            var path = Path()
            for (i, p) in points.enumerated() {
                let x = CGFloat(i) / CGFloat(points.count - 1) * size.width
                let y = size.height - CGFloat((p - mn) / span) * (size.height - 8) - 4
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(Color(hex: "#ffb347")), lineWidth: 1.5)
        }
    }
}

struct MovementSlot: Identifiable {
    let id: UUID
    var ticker: String
    var sigmaText: String
    var price: Double?
    var live: Bool
    var result: MovementResult?
}

struct MovementResult {
    var c, s, a, dx, dlss, mfmsp, node: Double
    var fmtC: String { MovementMath.fmt(c) }
    var fmtA: String { MovementMath.fmt(a) }
    var fmtDx: String { MovementMath.fmt(dx) }
    var fmtDlss: String { MovementMath.fmt(dlss) }
    var fmtMfmsp: String { MovementMath.fmt(mfmsp) }
    var fmtNode: String { MovementMath.fmt(node) }
}

enum MovementMath {
    static func stockphonic(radc: Double, rads: Double) -> (c: Double, s: Double, a: Double) {
        let c = radc * radc
        let s = max(rads, 1e-12)
        let a = sqrt(c / s)
        return (c, s, a)
    }
    static func eodpropg(radcEod: Double, a: Double) -> (dx: Double, dlss: Double) {
        let aa = max(a, 1e-12)
        let dx = radcEod / aa
        let ar = pow(dx, dx)
        let arr = sqrt(dx / max(ar, 1e-300))
        let gtx = aa * aa
        let rtx = aa * gtx
        let dlss = pow(rtx, arr)
        return (dx, dlss)
    }
    static func geopropg(a: Double, dlss: Double) -> (mfmsp: Double, node: Double) {
        let mfmsp = a * dlss
        let rmsp = cbrt(mfmsp)
        let node = pow(rmsp, dlss * 3)
        return (mfmsp, node)
    }
    static func fmt(_ n: Double) -> String {
        if !n.isFinite { return "N/A" }
        if abs(n) > 1e12 || (abs(n) < 1e-6 && n != 0) { return String(format: "%.3e", n) }
        return String(format: "%.4f", n)
    }
}

@MainActor
final class MovementViewModel: ObservableObject {
    @Published var slots: [MovementSlot] = [
        MovementSlot(id: UUID(), ticker: "AAPL", sigmaText: "1.0", price: nil, live: false, result: nil),
        MovementSlot(id: UUID(), ticker: "MSFT", sigmaText: "0.8", price: nil, live: false, result: nil)
    ]
    @Published var yearStart = "2020"
    @Published var yearEnd = "2080"
    @Published var eod = "1.0"
    @Published var status = "Enter tickers · fetch quotes · compute"
    @Published var lastResult: MovementResult?
    @Published var trajectory: [Double] = []

    func addSlot() {
        guard slots.count < 5 else { status = "Max 5 tickers"; return }
        slots.append(MovementSlot(id: UUID(), ticker: "", sigmaText: "1.0", price: nil, live: false, result: nil))
    }
    func removeSlot() {
        if slots.count > 1 { slots.removeLast() }
    }
    func reset() {
        for i in slots.indices {
            slots[i].price = nil; slots[i].live = false; slots[i].result = nil
        }
        lastResult = nil; trajectory = []; status = "RESET"
    }

    func compute() {
        let eodV = Double(eod) ?? 1.0
        let y0 = Int(yearStart) ?? 2020
        let y1 = Int(yearEnd) ?? 2080
        var last: MovementResult?
        for i in slots.indices {
            let px = slots[i].price ?? 0
            let sig = Double(slots[i].sigmaText) ?? 0
            guard px > 0, sig > 0 else { continue }
            let sp = MovementMath.stockphonic(radc: px, rads: sig)
            let e = MovementMath.eodpropg(radcEod: eodV * px, a: sp.a)
            let g = MovementMath.geopropg(a: sp.a, dlss: e.dlss)
            let r = MovementResult(c: sp.c, s: sp.s, a: sp.a, dx: e.dx, dlss: e.dlss, mfmsp: g.mfmsp, node: g.node)
            slots[i].result = r
            last = r
        }
        lastResult = last
        if let r = last {
            let years = max(y1 - y0, 1)
            trajectory = (0...min(years, 80)).map { i in
                let t = Double(i) / Double(max(years, 1))
                return r.node.isFinite ? r.a * (1 + t * 0.15) + (r.dlss.isFinite ? tanh(r.dlss) * t : 0) : r.a
            }
            status = "COMPUTED \(slots.compactMap { $0.ticker.isEmpty ? nil : $0.ticker }.joined(separator: ", "))"
        } else {
            status = "Need price + sigma on at least one slot"
        }
    }

    func fetchAll() async {
        for s in slots where !s.ticker.trimmingCharacters(in: .whitespaces).isEmpty {
            await fetch(s.id)
        }
    }

    func fetch(_ id: UUID) async {
        guard let i = slots.firstIndex(where: { $0.id == id }) else { return }
        let t = slots[i].ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !t.isEmpty else { status = "Enter a ticker first"; return }
        status = "FETCH \(t)…"
        if let q = await Self.quote(t) {
            slots[i].ticker = t
            slots[i].price = q.price
            slots[i].live = q.live
            status = q.live ? "LIVE \(t) \(String(format: "%.2f", q.price))" : "QUOTE \(t) \(String(format: "%.2f", q.price))"
        } else {
            status = "Quote failed for \(t)"
        }
    }

    static func quote(_ ticker: String) async -> (price: Double, live: Bool)? {
        let t = ticker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticker
        let gas = AutumnConfig.movementQuoteGAS + "?action=stockprice&ticker=\(t)&cb=_\(Int(Date().timeIntervalSince1970))"
        if let url = URL(string: gas),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ok = obj["ok"] as? Bool, ok,
           let price = obj["price"] as? Double, price > 0 {
            let live = obj["live"] as? Bool ?? true
            return (price, live)
        }
        let y = "https://query1.finance.yahoo.com/v8/finance/chart/\(t)?interval=1d&range=5d"
        if let url = URL(string: y),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chart = obj["chart"] as? [String: Any],
           let result = (chart["result"] as? [[String: Any]])?.first,
           let meta = result["meta"] as? [String: Any] {
            let price = (meta["regularMarketPrice"] as? Double)
                ?? (meta["previousClose"] as? Double)
                ?? 0
            if price > 0 { return (price, true) }
        }
        return nil
    }
}
