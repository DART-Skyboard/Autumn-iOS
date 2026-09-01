import SwiftUI
import UIKit
import LEATRCore
import AutumnServices

/// Afterlife Crossing — 1:1 port of index.html #alc-overlay + ALC IIFE (~28667).
/// Two vertical tabs: ALC calculator and DART Namography.
struct ALCStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var journalVM: JournalViewModel
    @State private var tab: AlcTab = .alc
    @StateObject private var calc = ALCCalculator()
    @StateObject private var namo = NamoEngine()

    enum AlcTab { case alc, namo }
    private var purple: Color { Color(hex: "#a050ff") }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture { appNav.studio = nil }
            VStack(spacing: 0) {
                HStack {
                    Text("✦ AFTERLIFE CROSSING")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(purple.opacity(0.85))
                    Spacer()
                    Button("✕") { appNav.studio = nil }
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(hex: "#ff4466").opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: "#ff4466").opacity(0.3), lineWidth: 1))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(purple.opacity(0.07))

                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 4) {
                        vtab("ALC", on: tab == .alc) { tab = .alc }
                        vtab("NAMO", on: tab == .namo) { tab = .namo }
                        Spacer()
                    }
                    .frame(width: 38)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35))

                    ScrollView {
                        if tab == .alc { alcPanel } else { namoPanel }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 680)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .background(Color(red: 6/255, green: 3/255, blue: 18/255).opacity(0.88))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(purple.opacity(0.28), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 24)
            .shadow(color: purple.opacity(0.18), radius: 24)
        }
        .transition(.opacity)
    }

    private func vtab(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .rotationEffect(.degrees(-90))
                .foregroundColor(on ? Color(hex: "#c88cff") : purple.opacity(0.45))
                .frame(width: 28, height: 64)
                .background(on ? purple.opacity(0.12) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? purple.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var alcPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    Image("HarpmakerV")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(purple.opacity(0.3), lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("“From the same where what is left off / what begins the same as itself where it won't begin.”")
                        .font(.system(size: 12).italic())
                        .foregroundColor(Color(hex: "#c88cff").opacity(0.9))
                    Text("— harpmaker")
                        .font(.system(size: 10))
                        .foregroundColor(purple.opacity(0.5))
                    Text("{ 2 Mercury Spheres · A Poster Stand · A Pocket Watch Navigation Desk · A Pantry Seasoning Dripbox }")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(purple.opacity(0.6))
                }
            }
            .padding(12)
            .background(Color(red: 75/255, green: 0, blue: 130/255).opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(purple.opacity(0.18), lineWidth: 1))
            .cornerRadius(8)

            Text("AFTER LIFE CROSSING AGE CALCULATOR")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(purple.opacity(0.7))

            Text("Number of People")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "#c8a0ff").opacity(0.7))
            Stepper(value: $calc.peopleCount, in: 1...20) {
                Text("\(calc.peopleCount)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .onChange(of: calc.peopleCount) { n in calc.generateInputs(n) }

            ForEach($calc.people) { $p in
                VStack(alignment: .leading, spacing: 6) {
                    Text("PERSON \(p.index)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(purple.opacity(0.55))
                    TextField("name", text: $p.name)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(purple.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(purple.opacity(0.2), lineWidth: 1))
                    HStack {
                        DatePicker("Birth", selection: $p.birth, displayedComponents: .date)
                            .labelsHidden()
                            .colorScheme(.dark)
                        DatePicker("Death", selection: $p.death, displayedComponents: .date)
                            .labelsHidden()
                            .colorScheme(.dark)
                    }
                }
                .padding(8)
                .background(purple.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(purple.opacity(0.1), lineWidth: 1))
            }

            HStack(spacing: 8) {
                Button("◈ Calculate") { calc.calculate(journal: journalVM) }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#c88cff"))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(purple.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(purple.opacity(0.4), lineWidth: 1))
                Button("⬆ Export to Ash Repo") { calc.export(auth: authVM) }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#00e5ff"))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(hex: "#00e5ff").opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#00e5ff").opacity(0.3), lineWidth: 1))
            }
            if !calc.result.isEmpty {
                Text(calc.result)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 75/255, green: 0, blue: 130/255).opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(purple.opacity(0.2), lineWidth: 1))
            }
            if let st = calc.status { Text(st).font(.system(size: 10, design: .monospaced)).foregroundColor(purple.opacity(0.6)) }
        }
        .onAppear { if calc.people.isEmpty { calc.generateInputs(calc.peopleCount) } }
    }

    private var namoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DART NAMOGRAPHY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(purple.opacity(0.7))
            Text("Total Name Character Combinations — Low, Moderate & High Diversity")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#c8aaff").opacity(0.6))
            HStack {
                TextField("e.g. Justin Craig Venable", text: $namo.query)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(purple.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(purple.opacity(0.2), lineWidth: 1))
                Button("Analyze") { Task { await namo.analyze(journal: journalVM) } }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#c88cff"))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(purple.opacity(0.16))
                Button("⬆ Export") { namo.export(auth: authVM) }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#00e5ff"))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(hex: "#00e5ff").opacity(0.07))
            }
            Text(namo.status)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(purple.opacity(0.55))

            HStack(alignment: .top, spacing: 10) {
                namoCol("Female Names", gender: "female")
                namoCol("Male Names", gender: "male")
            }
        }
    }

    private func namoCol(_ title: String, gender: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(Color(hex: "#c88cff"))
            ForEach(["low", "moderate", "high"], id: \.self) { lvl in
                namoBucket(gender: gender, level: lvl)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func namoBucket(gender: String, level: String) -> some View {
        let names = namo.filtered(gender: gender, level: level)
        let label = level == "low" ? "Low Diversity" : (level == "moderate" ? "Moderate" : "High Diversity")
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(label) (\(names.count))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(purple.opacity(0.6))
            HStack(spacing: 4) {
                TextField("Search", text: namo.filterBinding(gender: gender, level: level))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(purple.opacity(0.06))
                Button("Sort") { namo.sort(gender: gender, level: level) }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "#c88cff"))
                Button("Copy") { namo.copy(gender: gender, level: level) }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "#c88cff"))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(names, id: \.self) { n in
                        Text(n)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 140)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(purple.opacity(0.12), lineWidth: 1))
        }
    }
}

@MainActor
final class ALCCalculator: ObservableObject {
    struct Person: Identifiable {
        let id = UUID()
        var index: Int
        var name: String = ""
        var birth = Calendar.current.date(byAdding: .year, value: -70, to: Date()) ?? Date()
        var death = Date()
    }
    @Published var peopleCount = 1
    @Published var people: [Person] = []
    @Published var result = ""
    @Published var status: String? = nil

    func generateInputs(_ n: Int) {
        let n = min(20, max(1, n))
        peopleCount = n
        if people.count < n {
            for i in (people.count + 1)...n {
                people.append(Person(index: i))
            }
        } else if people.count > n {
            people = Array(people.prefix(n))
        }
        result = ""
    }

    func calculate(journal: JournalViewModel) {
        var lives: [(p: String, y: Double)] = []
        var total = 0.0
        for p in people {
            let yrs = p.death.timeIntervalSince(p.birth) / (365.25 * 24 * 3600)
            if yrs.isFinite && yrs > 0 {
                let label = p.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Person \(p.index)" : p.name
                lives.append((label, yrs)); total += yrs
            }
        }
        guard !lives.isEmpty else {
            result = "Please provide valid birth and death dates."
            return
        }
        lives.sort { $0.y < $1.y }
        let mean = total / Double(people.count)
        var out = String(format: "MEAN AGE OF GROUP: %.2f years\n\n", mean)
        out += "ORDER OF CROSSING (second life):\n"
        for l in lives { out += String(format: "  %@: %.2f years\n", l.p, l.y) }
        result = out
        journal.append(content: "ALC calculate people=\(lives.count) mean=\(String(format: "%.2f", mean))",
                       emotion: .spiritual, buoyancy: 0.6, isInternal: true)
    }

    func export(auth: AuthViewModel) {
        guard auth.githubConnected else {
            status = "Sign in with GitHub to export to your Ash repository."
            return
        }
        let payload: [String: Any] = [
            "tool": "calc",
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "uid": auth.sessionUID,
            "calc_result": result,
            "namo_query_len": NSNull(),
            "namo_counts": NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let content = String(data: data, encoding: .utf8) else { return }
        let filename = "alc_export_\(Int(Date().timeIntervalSince1970 * 1000)).json"
        let user = auth.githubUsername
        status = "Exporting…"
        Task {
            await UserVaultService.shared.write(folder: .exports, filename: filename, content: content, githubUsername: user)
            await MainActor.run { status = "Exported to your Ash repository" }
        }
    }
}

@MainActor
final class NamoEngine: ObservableObject {
    @Published var query = "Justin Craig Venable"
    @Published var status = ""
    @Published var fOrig: [String: [String]] = ["low": [], "moderate": [], "high": []]
    @Published var mOrig: [String: [String]] = ["low": [], "moderate": [], "high": []]
    @Published var fLists: [String: [String]] = ["low": [], "moderate": [], "high": []]
    @Published var mLists: [String: [String]] = ["low": [], "moderate": [], "high": []]
    @Published var filters: [String: String] = [:]
    var sorts: [String: Bool] = [:]

    func filterBinding(gender: String, level: String) -> Binding<String> {
        let key = gender + "_" + level
        return Binding(
            get: { self.filters[key] ?? "" },
            set: { self.filters[key] = $0; self.applyFilter(gender: gender, level: level) }
        )
    }

    func filtered(gender: String, level: String) -> [String] {
        Array(Set(gender == "female" ? (fLists[level] ?? []) : (mLists[level] ?? [])))
    }

    func analyze(journal: JournalViewModel) async {
        let inp = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inp.isEmpty else { status = "Enter a name."; return }
        status = "Fetching NYC baby name dataset…"
        let url = URL(string: "https://data.cityofnewyork.us/resource/25th-nujf.json?$select=nm,gndr,sum(cnt)%20as%20cnt&$group=nm,gndr&$limit=50000")!
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Autumn-iOS/1.0.2 (leatr.xyz)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                status = "Error: unexpected dataset"; return
            }
            var counts: [Character: Int] = [:]
            for c in inp.lowercased() where c.isLetter { counts[c, default: 0] += 1 }
            func isSubset(_ word: String) -> Bool {
                var wc: [Character: Int] = [:]
                for ch in word {
                    wc[ch, default: 0] += 1
                    if counts[ch, default: 0] < wc[ch, default: 0] { return false }
                }
                return true
            }
            var females: [(name: String, count: Int)] = []
            var males: [(name: String, count: Int)] = []
            for item in rows {
                let nm = ((item["nm"] as? String) ?? "").lowercased()
                let cnt = Int(item["cnt"] as? String ?? "") ?? (item["cnt"] as? Int) ?? 0
                if !isSubset(nm) { continue }
                if (item["gndr"] as? String) == "FEMALE" { females.append((nm, cnt)) }
                else { males.append((nm, cnt)) }
            }
            func categorize(_ arr: [(name: String, count: Int)]) -> [String: [String]] {
                if arr.isEmpty { return ["low": [], "moderate": [], "high": []] }
                let sorted = arr.sorted { $0.count > $1.count }
                let L = sorted.count
                let lowCut = sorted[Int(Double(L) * 0.1)].count
                let modCut = sorted[Int(Double(L) * 0.5)].count
                return [
                    "low": sorted.filter { $0.count >= lowCut }.map(\.name),
                    "moderate": sorted.filter { $0.count >= modCut }.map(\.name),
                    "high": Array(Set(sorted.map(\.name)))
                ]
            }
            var fc = categorize(females)
            let mc = categorize(males)
            let inV = males.map(\.name).filter { $0.hasSuffix("in") }.map { $0 + "e" }
            fc["high"] = Array(Set((fc["high"] ?? []) + inV))
            fOrig = fc; mOrig = mc; fLists = fc; mLists = mc
            status = "Analysis complete."
            journal.append(content: "ALC namography nameLen=\(inp.count)", emotion: .spiritual, buoyancy: 0.55, isInternal: true)
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    func applyFilter(gender: String, level: String) {
        let q = (filters[gender + "_" + level] ?? "").lowercased()
        let src = gender == "female" ? (fOrig[level] ?? []) : (mOrig[level] ?? [])
        let filt = q.isEmpty ? src : src.filter { $0.contains(q) }
        if gender == "female" { fLists[level] = filt } else { mLists[level] = filt }
    }

    func sort(gender: String, level: String) {
        let key = gender + "_" + level
        sorts[key] = !(sorts[key] ?? false)
        let d = (sorts[key] ?? false) ? true : false
        if gender == "female" {
            fLists[level] = (fLists[level] ?? []).sorted { d ? $0 < $1 : $0 > $1 }
        } else {
            mLists[level] = (mLists[level] ?? []).sorted { d ? $0 < $1 : $0 > $1 }
        }
    }

    func copy(gender: String, level: String) {
        let list = filtered(gender: gender, level: level)
        UIPasteboard.general.string = list.joined(separator: "\n")
        status = "Copied \(list.count) names"
    }

    func export(auth: AuthViewModel) {
        guard auth.githubConnected else {
            status = "Sign in with GitHub to export to your Ash repository."
            return
        }
        let payload: [String: Any] = [
            "tool": "namo",
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "uid": auth.sessionUID,
            "calc_result": NSNull(),
            "namo_query_len": query.trimmingCharacters(in: .whitespaces).count,
            "namo_counts": [
                "fLow": fLists["low"]?.count ?? 0, "fMod": fLists["moderate"]?.count ?? 0, "fHigh": fLists["high"]?.count ?? 0,
                "mLow": mLists["low"]?.count ?? 0, "mMod": mLists["moderate"]?.count ?? 0, "mHigh": mLists["high"]?.count ?? 0
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let content = String(data: data, encoding: .utf8) else { return }
        let filename = "alc_export_\(Int(Date().timeIntervalSince1970 * 1000)).json"
        let user = auth.githubUsername
        status = "Exporting…"
        Task {
            await UserVaultService.shared.write(folder: .exports, filename: filename, content: content, githubUsername: user)
            await MainActor.run { status = "Exported to your Ash repository" }
        }
    }
}
