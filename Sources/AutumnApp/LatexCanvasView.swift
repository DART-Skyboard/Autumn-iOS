import SwiftUI
import UIKit
import LEATRCore
import AutumnServices

/// LaTeX canvas overlay — generate examples on-canvas, export TeX / MathML / PNG / SVG / CSV / ODT.
struct LatexCanvasOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @State private var source: String = "(a+b)^2 = a^2 + 2ab + b^2"
    @State private var title: String = "Algebra identity"
    @State private var note: String = ""
    @State private var exportMessage: String = ""
    @State private var showShare = false
    @State private var shareItems: [Any] = []

    var body: some View {
        // TF102: the width fix (TF101) didn't address height — in landscape the
        // card's natural content height (title field + glyph canvas + source
        // editor + buttons, each with fixed minHeights) easily exceeds the
        // available landscape height, so the bottom of the card rendered off
        // the edge of the screen with no way to reach it. Now sizes height off
        // GeometryReader too, and the body below the header scrolls internally
        // when it doesn't fit — the whole overlay and everything in it stays
        // reachable in either orientation instead of just resizing the frame
        // around content that still overflows it.
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let cardWidth = landscape
                ? min(620, max(320, geo.size.width * 0.46))
                : min(620, geo.size.width * 0.94)
            let cardHeight = min(640, geo.size.height * (landscape ? 0.92 : 0.86))
            latexCard(width: cardWidth, height: cardHeight)
        }
    }

    private func latexCard(width: CGFloat, height: CGFloat) -> some View {
        let chrome = themeVM.chrome
        return ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { appNav.showLatexCanvas = false }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("LATEX CANVAS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(chrome.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    Menu("EXPORT") {
                        Button("LaTeX (.tex)") { exportTeX() }
                        Button("MathML (.mml)") { exportMathML() }
                        Button("PNG transparent") { exportPNG() }
                        Button("SVG (.svg)") { exportSVG() }
                        Button("CSV spreadsheet") { exportCSV() }
                        Button("OpenDocument (.odt)") { exportODT() }
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent)
                    Button("✕") { appNav.showLatexCanvas = false }
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(14)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Title", text: $title)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)

                        LatexGlyphCanvas(source: source)
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .padding(12)
                            .background(Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(chrome.accent.opacity(0.25), lineWidth: 1))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)

                        Text("LaTeX source")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 14)
                        TextEditor(text: $source)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 70)
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                            .padding(.horizontal, 14)

                        if !note.isEmpty {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.top, 6)
                        }
                        if !exportMessage.isEmpty {
                            Text(exportMessage)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(chrome.accent)
                                .padding(.horizontal, 14)
                                .padding(.top, 4)
                        }

                        HStack {
                            Button("Example (a+b)²") { loadIdentity(AlgebraIdentities.example(for: "square")) }
                            Button("F = ma") { loadIdentity(AlgebraIdentities.example(for: "force")) }
                            Button("Advanced") { loadAdvanced() }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent)
                        .padding(14)
                    }
                }
            }
            .frame(maxWidth: width, maxHeight: height)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.5))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(chrome.accent.opacity(0.35), lineWidth: 1))
            .padding(16)
        }
        .onAppear { seedFromNav() }
        .sheet(isPresented: $showShare) {
            ActivityShareView(items: shareItems)
        }
    }

    private func seedFromNav() {
        let seed = appNav.latexSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seed.isEmpty {
            if seed.lowercased().contains("advanced") && seed.lowercased().contains("latex") {
                loadAdvanced()
                return
            }
            if let id = AlgebraIdentities.match(seed) {
                loadIdentity(id)
            } else if let stmt = MathParser.parse(MathNL.toExpr(seed) ?? seed) {
                source = stmt.latex
                title = seed
                note = "Generated from chat / Math Solver."
            } else {
                source = seed
                title = seed
            }
        } else {
            loadIdentity(AlgebraIdentities.example(for: "square"))
        }
    }

    private func loadIdentity(_ id: AlgebraIdentity) {
        source = id.latex
        title = id.name
        note = id.note
        MathWorkspaceHolder.current.remember(prompt: id.name, report: id.expansion, identity: id.id)
    }

    private func loadAdvanced() {
        source = """
        \\[ \\Delta = b^{2}-4ac,\\quad
        x = \\frac{-b \\pm \\sqrt{\\Delta}}{2a},\\quad
        (a+b)^{3} = a^{3}+3a^{2}b+3ab^{2}+b^{3},\\quad
        F = m a,\\quad
        \\Gamma(n)=(n-1)! \\]
        """
        title = "Advanced LaTeX — identities & physics"
        note = "Discriminant, quadratic, cube identity, Newton II, Gamma."
    }

    private func exportTeX() {
        let body = """
        % Autumn / Sentient Journal LaTeX export
        \\documentclass{article}
        \\usepackage{amsmath}
        \\begin{document}
        \\section*{\(title)}
        \\[
        \(source)
        \\]
        \\end{document}
        """
        share(filename: "autumn-math.tex", data: Data(body.utf8), type: "tex")
    }

    private func exportMathML() {
        let inner: String
        if let stmt = MathParser.parse(MathNL.toExpr(source) ?? source) {
            switch stmt {
            case .expr(let n): inner = n.mathML
            case .assign(let v, let n): inner = MathML.wrap("<mrow><mi>\(v)</mi><mo>=</mo>\(MathML.inner(n))</mrow>")
            case .equation(let l, let r): inner = MathML.wrap("<mrow>\(MathML.inner(l))<mo>=</mo>\(MathML.inner(r))</mrow>")
            case .text(let t): inner = MathML.wrap("<mtext>\(t)</mtext>")
            }
        } else {
            inner = MathML.wrap("<mtext>\(source)</mtext>")
        }
        share(filename: "autumn-math.mml", data: Data(inner.utf8), type: "mml")
    }

    private func exportPNG() {
        let view = LatexGlyphCanvas(source: source)
            .frame(width: 720, height: 240)
            .background(Color.clear)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = false
        guard let img = renderer.uiImage, let data = img.pngData() else {
            exportMessage = "PNG render failed."
            return
        }
        share(filename: "autumn-math.png", data: data, type: "png")
    }

    /// Vector SVG from the same pretty()/layout text the canvas and PNG use (not a raster wrap).
    private func exportSVG() {
        let display = LatexGlyphCanvas.pretty(source)
        let rawLines = display.components(separatedBy: .newlines)
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let contentLines = lines.isEmpty ? [display.isEmpty ? " " : display] : lines

        let fontSize: CGFloat = 28
        let lineHeight = fontSize * 1.35
        let padding: CGFloat = 16
        let maxChars = max(contentLines.map(\.count).max() ?? 1, 1)
        // Serif math glyph advance ≈ 0.55em — sizes viewBox to content like the on-canvas layout.
        let textWidth = CGFloat(maxChars) * fontSize * 0.55
        let width = max(ceil(textWidth + padding * 2), 120)
        let height = max(ceil(CGFloat(contentLines.count) * lineHeight + padding * 2), 64)

        func xmlEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }

        var textElems = ""
        for (i, line) in contentLines.enumerated() {
            let y = padding + fontSize + CGFloat(i) * lineHeight
            let x = width / 2
            textElems += """
              <text x="\(String(format: "%.1f", x))" y="\(String(format: "%.1f", y))" text-anchor="middle" dominant-baseline="alphabetic" font-family="Georgia, 'Times New Roman', Times, serif" font-size="\(Int(fontSize))" font-weight="500" fill="#FFFFFF">\(xmlEscape(line))</text>

            """
        }

        // Transparent background (matches PNG export intent); white glyphs for dark/canvas contrast.
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(width))" height="\(Int(height))" viewBox="0 0 \(String(format: "%.1f", width)) \(String(format: "%.1f", height))">
        <!-- Autumn LaTeX canvas — vector export from math layout text; transparent bg -->
        \(textElems.trimmingCharacters(in: .whitespacesAndNewlines))
        </svg>
        """
        share(filename: "autumn-math.svg", data: Data(svg.utf8), type: "svg")
    }

    private func exportCSV() {
        var rows = ["kind,name,value"]
        rows.append("title,\(csv(title)),")
        rows.append("latex,\(csv(source)),")
        rows.append("note,\(csv(note)),")
        for (k, v) in MathWorkspaceHolder.current.env.sorted(by: { $0.key < $1.key }) {
            rows.append("variable,\(csv(k)),\(v)")
        }
        for id in AlgebraIdentities.catalog {
            rows.append("identity,\(csv(id.name)),\(csv(id.expansion))")
        }
        share(filename: "autumn-math.csv", data: Data(rows.joined(separator: "\n").utf8), type: "csv")
    }

    private func exportODT() {
        let text = "\(title)\n\n\(source)\n\n\(note)"
        if let data = MinimalODT.document(text: text) {
            share(filename: "autumn-math.odt", data: data, type: "odt")
        } else {
            exportMessage = "ODT write failed."
        }
    }

    private func csv(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func share(filename: String, data: Data, type: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            shareItems = [url]
            showShare = true
            exportMessage = "Exported \(filename) (\(type))."
            MathWorkspaceHolder.current.remember(
                prompt: "export \(type)",
                report: filename,
                identity: nil
            )
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

struct LatexGlyphCanvas: View {
    let source: String
    var body: some View {
        let display = Self.pretty(source)
        VStack(spacing: 8) {
            Text(display)
                .font(.system(size: 28, weight: .medium, design: .serif))
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
    }

    /// Shared layout text used by on-canvas render, PNG ImageRenderer, and SVG vector export.
    static func pretty(_ source: String) -> String {
        var s = source
        let reps = [
            ("\\cdot", "·"), ("\\times", "×"), ("\\pm", "±"),
            ("\\Delta", "Δ"), ("\\Gamma", "Γ"), ("\\zeta", "ζ"),
            ("\\pi", "π"), ("\\theta", "θ"), ("\\lambda", "λ"),
            ("\\alpha", "α"), ("\\beta", "β"), ("\\sigma", "σ"),
            ("\\omega", "ω"), ("\\phi", "φ"), ("\\sqrt", "√"),
            ("\\frac", "/"), ("\\left", ""), ("\\right", ""),
            ("\\operatorname", ""), ("\\quad", "   "),
            ("\\[", ""), ("\\]", ""), ("\\(", ""), ("\\)", ""),
            ("^{2}", "²"), ("^{3}", "³"), ("^{4}", "⁴"),
            ("^2", "²"), ("^3", "³"), ("^4", "⁴"),
            ("{", ""), ("}", ""), ("\\\\", " ")
        ]
        for (a, b) in reps { s = s.replacingOccurrences(of: a, with: b) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Minimal ODT (uncompressed ZIP) — no Google Docs API.
enum MinimalODT {
    static func document(text: String) -> Data? {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let paras = escaped.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<text:p>\($0)</text:p>" }
            .joined()
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
        <office:body><office:text>\(paras)</office:text></office:body>
        </office:document-content>
        """
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">
        <manifest:file-entry manifest:media-type="application/vnd.oasis.opendocument.text" manifest:full-path="/"/>
        <manifest:file-entry manifest:media-type="text/xml" manifest:full-path="content.xml"/>
        </manifest:manifest>
        """
        return zipStore(files: [
            ("mimetype", Array("application/vnd.oasis.opendocument.text".utf8)),
            ("content.xml", Array(content.utf8)),
            ("META-INF/manifest.xml", Array(manifest.utf8))
        ])
    }

    /// ZIP stored (method 0) — good enough for ODT readers.
    static func zipStore(files: [(String, [UInt8])]) -> Data {
        var local = Data()
        var central = Data()
        var offset: UInt32 = 0
        for (name, bytes) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(bytes)
            let sz = UInt32(bytes.count)
            var loc = Data()
            loc.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
            loc.append(contentsOf: u16(20))
            loc.append(contentsOf: u16(0))
            loc.append(contentsOf: u16(0))
            loc.append(contentsOf: u16(0))
            loc.append(contentsOf: u16(0))
            loc.append(contentsOf: u32(crc))
            loc.append(contentsOf: u32(sz))
            loc.append(contentsOf: u32(sz))
            loc.append(contentsOf: u16(UInt16(nameData.count)))
            loc.append(contentsOf: u16(0))
            loc.append(nameData)
            loc.append(contentsOf: bytes)
            var cen = Data()
            cen.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
            cen.append(contentsOf: u16(20))
            cen.append(contentsOf: u16(20))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u32(crc))
            cen.append(contentsOf: u32(sz))
            cen.append(contentsOf: u32(sz))
            cen.append(contentsOf: u16(UInt16(nameData.count)))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u32(0))
            cen.append(contentsOf: u32(offset))
            cen.append(nameData)
            offset += UInt32(loc.count)
            local.append(loc)
            central.append(cen)
        }
        var end = Data()
        end.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        end.append(contentsOf: u16(0))
        end.append(contentsOf: u16(0))
        end.append(contentsOf: u16(UInt16(files.count)))
        end.append(contentsOf: u16(UInt16(files.count)))
        end.append(contentsOf: u32(UInt32(central.count)))
        end.append(contentsOf: u32(UInt32(local.count)))
        end.append(contentsOf: u16(0))
        var out = Data()
        out.append(local)
        out.append(central)
        out.append(end)
        return out
    }

    private static func u16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]
    }
    private static func u32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }
    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for b in bytes {
            let idx = Int((crc ^ UInt32(b)) & 0xff)
            crc = crc32table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
    private static let crc32table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()
}

enum MathIntent {
    static func wantsLatexCanvas(_ raw: String) -> Bool {
        let s = raw.lowercased()
        if s.range(of: #"\b(show|render|draw|open)\b"#, options: .regularExpression) == nil
            && !s.contains("example") && !s.contains("latex") {
            return false
        }
        return s.contains("latex")
            || s.contains("mathml")
            || (s.contains("example") && (s.contains("math") || s.contains("algebra") || s.contains("identity") || s.contains("advanced")))
            || s.contains("show me an example")
            || s.contains("show an example")
    }

    static func wantsMathSolver(_ raw: String) -> Bool {
        let s = raw.lowercased()
        return s.contains("math solver") || s.contains("open fx") || s.contains("context assignment")
    }

    static func seed(for raw: String) -> String {
        if let id = AlgebraIdentities.match(raw) { return id.latex }
        if raw.lowercased().contains("advanced") {
            return AlgebraIdentities.example(for: raw).latex
        }
        return AlgebraIdentities.example(for: raw).latex
    }
}
