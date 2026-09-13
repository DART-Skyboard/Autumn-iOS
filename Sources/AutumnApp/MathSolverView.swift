import SwiftUI
import LEATRCore
import AutumnServices

/// Web `fx` Math Solver & Context Assignment — specialOperator / physicsField / mathOperation.
struct MathSolverOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var chatVM: ChatViewModel
    @State private var equation: String = "F = m * a"
    @State private var selectedVar: String = ""
    @State private var valueText: String = ""
    @State private var specialOp: String = ""
    @State private var mathOp: String = ""
    @State private var physics: String = ""
    @State private var report: String = "No contexts assigned yet."
    @State private var batch: [String] = []

    var variables: [String] {
        let chars = equation.filter { $0.isLetter || $0 == "_" }
        var seen: [String] = []
        // Prefer parsed symbols when possible
        if let stmt = MathParser.parse(equation) {
            let vs: Set<String>
            switch stmt {
            case .expr(let n): vs = n.variables()
            case .assign(let name, let n): vs = n.variables().union([name])
            case .equation(let l, let r): vs = l.variables().union(r.variables())
            case .text: vs = []
            }
            return vs.sorted()
        }
        for ch in chars {
            let s = String(ch)
            if !seen.contains(s) { seen.append(s) }
        }
        return seen
    }

    var body: some View {
        let chrome = themeVM.chrome
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { appNav.showMathSolver = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("MATH SOLVER & CONTEXT")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(chrome.accent)
                    Spacer()
                    Button("LATEX") {
                        appNav.latexSeed = equation
                        appNav.showLatexCanvas = true
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent)
                    Button("✕") { appNav.showMathSolver = false }
                        .foregroundColor(.white.opacity(0.6))
                }
                Text("Equation / Formula")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                TextEditor(text: $equation)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 56)
                    .padding(6)
                    .background(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(chrome.accent.opacity(0.3), lineWidth: 1))

                HStack {
                    Picker("Variable", selection: $selectedVar) {
                        Text("-- Variable --").tag("")
                        ForEach(variables, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(chrome.accent)
                    Button("Assign ↓") { assignContext() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent)
                    Button("Clear") { clearSelected() }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                HStack {
                    Text("Value")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    TextField("numerical value or expression", text: $valueText)
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(6)
                    Button("Add") { addValue() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent)
                }

                VStack(spacing: 6) {
                    picker("Special Operator", selection: $specialOp, items: MathGlossary.specialOperators)
                    picker("Math Operation", selection: $mathOp, items: MathGlossary.mathOperations)
                    picker("Physics Field", selection: $physics, items: MathGlossary.physicsFields)
                }

                ScrollView {
                    Text(report)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)

                HStack {
                    Button("Add to Batch") { addToBatch() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent)
                    Button("Solve Batch") { solveBatch() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(chrome.accent.opacity(0.25))
                        .cornerRadius(6)
                    Spacer()
                    Button("Send to Chat") { sendToChat() }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(chrome.accent)
                }
            }
            .padding(16)
            .frame(maxWidth: 560)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.45))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(chrome.accent.opacity(0.35), lineWidth: 1))
            .padding(18)
        }
        .onAppear {
            if !appNav.mathSeed.isEmpty { equation = appNav.mathSeed }
            refreshReport()
        }
    }

    private func picker(_ title: String, selection: Binding<String>, items: [(id: String, label: String)]) -> some View {
        Picker(title, selection: selection) {
            Text("-- \(title) --").tag("")
            ForEach(items, id: \.id) { Text($0.label).tag($0.id) }
        }
        .pickerStyle(.menu)
        .tint(themeVM.chrome.accent)
    }

    private func assignContext() {
        guard !selectedVar.isEmpty else { return }
        var ctx = MathWorkspaceHolder.current.contexts[selectedVar]
            ?? MathVarContext(name: selectedVar)
        if !specialOp.isEmpty { ctx.specialOperator = specialOp }
        if !physics.isEmpty { ctx.physicsField = physics }
        if !mathOp.isEmpty { ctx.mathOperation = mathOp }
        if !valueText.isEmpty { ctx.valueExpr = valueText }
        MathWorkspaceHolder.current.assignContext(ctx)
        specialOp = ""; physics = ""; mathOp = ""
        refreshReport()
    }

    private func addValue() {
        guard !selectedVar.isEmpty, !valueText.isEmpty else { return }
        var ctx = MathWorkspaceHolder.current.contexts[selectedVar]
            ?? MathVarContext(name: selectedVar)
        ctx.valueExpr = valueText
        MathWorkspaceHolder.current.assignContext(ctx)
        refreshReport()
    }

    private func clearSelected() {
        guard !selectedVar.isEmpty else { return }
        MathWorkspaceHolder.current.contexts.removeValue(forKey: selectedVar)
        MathWorkspaceHolder.current.env.removeValue(forKey: selectedVar)
        refreshReport()
    }

    private func addToBatch() {
        let lines = equation.split(whereSeparator: { $0 == "\n" || $0 == ";" }).map(String.init)
        batch.append(contentsOf: lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        refreshReport()
    }

    private func solveBatch() {
        var prompts = batch
        if prompts.isEmpty {
            prompts = equation.split(whereSeparator: { $0 == "\n" || $0 == ";" }).map { String($0) }
        }
        var ws = MathWorkspaceHolder.current
        let result = BRPNMathBatch.process(prompts, workspace: &ws)
        MathWorkspaceHolder.current = ws
        report = result.report
        batch = []
    }

    private func sendToChat() {
        let text = report.contains("Prompt:") ? report : equation
        Task { await chatVM.injectAndSend(text.contains("=") ? equation : text) }
        appNav.showMathSolver = false
    }

    private func refreshReport() {
        let ctxs = MathWorkspaceHolder.current.contexts
        if ctxs.isEmpty && batch.isEmpty {
            report = "No contexts assigned yet."
        } else {
            let c = ctxs.values.map(\.summary).joined(separator: "\n")
            let b = batch.isEmpty ? "" : "\nBatch:\n" + batch.joined(separator: "\n")
            report = c + b
        }
    }
}
