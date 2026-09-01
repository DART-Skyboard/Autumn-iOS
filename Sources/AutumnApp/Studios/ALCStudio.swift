import SwiftUI
import LEATRCore
import AutumnServices

/// Afterlife Crossing — ALC calculator & DART namography (web `alcOverlayToggle`).
struct ALCStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var name = "Autumn"
    @State private var crossing: Double = 1.0
    @State private var result = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("AFTERLIFE CROSSING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#a050ff"))
                Text("DART namography. DOC replaces π. Crossing is finite — reflex never loops. Core Cognition stays True.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                TextField("name", text: $name)
                    .textFieldStyle(.plain).foregroundColor(.white)
                    .padding(8).background(themeVM.chrome.surface).cornerRadius(6)
                SliderControl(label: "CROSSING", value: $crossing, range: 0.1...12, format: "%.2f")
                Button("⬡ COMPUTE ALC") { compute() }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#a050ff"))
                if !result.isEmpty {
                    Text(result)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#a050ff").opacity(0.08))
                        .cornerRadius(6)
                }
                Text("C = √(d × DOC)²   DOC = \(LEATRIdentity.DOC)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }.padding(16)
        }
    }

    private func compute() {
        let d = max(crossing, 0.1)
        let circ = LEATRIdentity.arcEdgeCircumference(diameter: d)
        let n = name.utf8.reduce(0) { $0 &+ Int($1) }
        let node = Double(n % 97) / 97.0
        result = String(format: "NAME %@\nCIRC %.4f\nNODE %.4f\nALC  %.4f\nTRUE",
                        name.uppercased(), circ, node, circ * (1 + node) / d)
    }
}
