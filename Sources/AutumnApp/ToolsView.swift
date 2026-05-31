import SwiftUI
import LEATRCore

// MARK: — Tools View
public struct ToolsView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var selected: ToolPanel = .arcEdge

    enum ToolPanel: String, CaseIterable {
        case arcEdge  = "Arc Edge"
        case arcLake  = "ArcLake"
        case calc     = "CALC"
        case emoMap   = "EMO MAP"
    }

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()
            VStack(spacing: 0) {
                // Tool selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ToolPanel.allCases, id: \.self) { panel in
                            Button {
                                withAnimation { selected = panel }
                            } label: {
                                Text(panel.rawValue)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selected == panel
                                        ? themeVM.current.accent.opacity(0.2)
                                        : themeVM.current.surface)
                                    .foregroundColor(selected == panel
                                        ? themeVM.current.accent
                                        : themeVM.current.textSecondary)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selected == panel
                                                ? themeVM.current.accent.opacity(0.5)
                                                : Color.clear, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(.ultraThinMaterial)

                // Panel content
                switch selected {
                case .arcEdge: ArcEdgePanel()
                case .arcLake: ArcLakePanel()
                case .calc:    CalcPanel()
                case .emoMap:  EmoMapPanel()
                }
            }
        }
    }
}

// MARK: — Arc Edge Panel
struct ArcEdgePanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var diameter: Double = 10.0
    @State private var deviationX: Double = 0.5
    @State private var deviationY: Double = 0.3
    @State private var arcResolution: Double = 64

    var circumference: Double { LEATRIdentity.arcEdgeCircumference(diameter: diameter) }
    var docPerimeter: String { String(format: "%.4f DOC units", circumference) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ARC EDGE STUDIO")
                            .font(.custom("Orbitron-Bold", size: 16))
                            .foregroundColor(themeVM.current.accent)
                        Text("DOC = \(LEATRIdentity.DOC, specifier: "%.1f") · C = √(d × DOC)²")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(themeVM.current.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                // Readout
                VStack(alignment: .leading, spacing: 8) {
                    Text("PERIMETER:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                    Text(docPerimeter)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.current.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(theme: themeVM.current)
                .padding(.horizontal, 16)

                // Controls
                Group {
                    SliderControl(label: "DIAMETER", value: $diameter, range: 0.1...100, format: "%.2f")
                    SliderControl(label: "DEVIATION X", value: $deviationX, range: 0...2, format: "%.3f")
                    SliderControl(label: "DEVIATION Y", value: $deviationY, range: 0...2, format: "%.3f")
                    SliderControl(label: "ARC RESOLUTION", value: $arcResolution, range: 8...256, format: "%.0f")
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: — ArcLake Panel
struct ArcLakePanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var selectedPreset = "Water H₂O"
    @State private var temperature: Double = 25.0
    @State private var pressure: Double = 101.325

    let presets = ["Water H₂O","CO₂","NaCl","Steel Fe+C+Cr","Titanium Ti+Al",
                   "Hercules Alloy","Copper Oxide","Calcium Carbonate","Silicon Dioxide","Iron+Copper"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("ARCLAKE STUDIO")
                    .font(.custom("Orbitron-Bold", size: 16))
                    .foregroundColor(themeVM.current.accent)
                    .padding(.horizontal, 16)

                // Preset selector
                Picker("Preset", selection: $selectedPreset) {
                    ForEach(presets, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .tint(themeVM.current.accent)

                SliderControl(label: "TEMPERATURE (°C)", value: $temperature, range: -273...6000, format: "%.1f")
                    .padding(.horizontal, 16)
                SliderControl(label: "PRESSURE (kPa)", value: $pressure, range: 0...10000, format: "%.3f")
                    .padding(.horizontal, 16)

                // CFD readout placeholder
                VStack(alignment: .leading, spacing: 8) {
                    Text("CFD SIMULATION")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                    Text("\(selectedPreset) @ \(temperature, specifier: "%.1f")°C, \(pressure, specifier: "%.1f") kPa")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                    Text("DART Reflex: f(d) = ((d×2)+1)/d")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeVM.current.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(theme: themeVM.current)
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: — CALC Panel
struct CalcPanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var display = "0"
    @State private var expression = ""

    var body: some View {
        VStack(spacing: 0) {
            // Display
            VStack(alignment: .trailing, spacing: 4) {
                Text(expression)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
                    .lineLimit(2)
                Text(display)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(20)

            Divider().background(themeVM.current.accent.opacity(0.3))

            // Keypad (placeholder)
            Text("Calculator — math.js integration")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(themeVM.current.textSecondary)
                .padding(40)
        }
    }
}

// MARK: — EMO MAP Panel
struct EmoMapPanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("EMOTION MAP")
                    .font(.custom("Orbitron-Bold", size: 16))
                    .foregroundColor(themeVM.current.accent)
                    .padding(.horizontal, 16)

                // All 21 emotions as colored tiles
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(EmotionType.allCases, id: \.self) { emotion in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: emotion.accentHex))
                                .frame(width: 28, height: 28)
                            Text(emotion.displayName)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        .padding(10)
                        .glassCard(theme: themeVM.current)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: — Reusable Slider Control
struct SliderControl: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeVM.current.accent)
            }
            Slider(value: $value, in: range)
                .tint(themeVM.current.accent)
        }
    }
}