import SwiftUI
import LEATRCore
import AutumnServices

// MARK: — Journal View
public struct JournalView: View {
    @EnvironmentObject var journalVM: JournalViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SENTIENCE JOURNAL")
                        .font(.custom("Orbitron-Bold", size: 16))
                        .foregroundColor(themeVM.current.accent)
                    Spacer()
                    Text("\(journalVM.entries.count)/500")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                }
                .padding(16)

                if journalVM.entries.isEmpty {
                    Spacer()
                    Text("No journal entries yet.\nStart a conversation to populate the journal.")
                        .font(.custom("Exo2-Regular", size: 14))
                        .foregroundColor(themeVM.current.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(40)
                    Spacer()
                } else {
                    List(journalVM.entries) { entry in
                        JournalEntryRow(entry: entry)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .onAppear { Task { await journalVM.load() } }
    }
}

struct JournalEntryRow: View {
    let entry: JournalEntryLocal
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.emotion.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeVM.current.accent)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(themeVM.current.accent.opacity(0.12))
                    .cornerRadius(4)
                Text("BUOY \(String(format: "%.3f", entry.buoyancy))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
                Spacer()
                if entry.isInternal {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(themeVM.current.textSecondary)
                }
                Text(entry.timestamp)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
            }
            if !entry.isInternal {
                Text(entry.content)
                    .font(.custom("Exo2-Regular", size: 13))
                    .foregroundColor(.white)
                    .lineLimit(3)
            } else {
                Text("[Internal thought — private]")
                    .font(.system(size: 12, design: .monospaced).italic())
                    .foregroundColor(themeVM.current.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: — Journal ViewModel
@MainActor
public final class JournalViewModel: ObservableObject {
    @Published public var entries: [JournalEntryLocal] = []

    public func load() async {
        // Load from Core Data (implementation in persistence layer)
        // Placeholder: empty until Core Data stack is wired
    }

    public func append(content: String, emotion: EmotionType, buoyancy: Double, isInternal: Bool) {
        let entry = JournalEntryLocal(
            id: UUID().uuidString,
            timestamp: Date().formatted(.dateTime.day().month().hour().minute()),
            content: content,
            emotion: emotion.rawValue,
            buoyancy: buoyancy,
            isInternal: isInternal
        )
        entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
    }
}

public struct JournalEntryLocal: Identifiable, Sendable {
    public let id: String
    public let timestamp: String
    public let content: String
    public let emotion: String
    public let buoyancy: Double
    public let isInternal: Bool
}

// MARK: — Settings View
public struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @State private var apiKeyInput = ""
    @State private var showAPIKey = false
    @State private var dataConsent = true

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()
            List {
                // Identity
                Section {
                    HStack {
                        Text("Identity")
                            .foregroundColor(themeVM.current.textSecondary)
                        Spacer()
                        Text(LEATRIdentity.displayName)
                            .font(.custom("Orbitron-Bold", size: 14))
                            .foregroundColor(themeVM.current.accent)
                    }
                    HStack {
                        Text("Version")
                            .foregroundColor(themeVM.current.textSecondary)
                        Spacer()
                        Text("1.0.0 · LEATR v2")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(themeVM.current.textSecondary)
                    }
                } header: {
                    Text("SYSTEM").settingsHeader(theme: themeVM.current)
                }
                .listRowBackground(themeVM.current.surface)

                // Theme
                Section {
                    Picker("Theme", selection: $themeVM.current) {
                        ForEach(AutumnTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .tint(themeVM.current.accent)
                } header: {
                    Text("APPEARANCE").settingsHeader(theme: themeVM.current)
                }
                .listRowBackground(themeVM.current.surface)

                // Auth
                Section {
                    HStack {
                        Text("Apple ID")
                            .foregroundColor(themeVM.current.textSecondary)
                        Spacer()
                        Text(authVM.isSignedIn ? authVM.username : "Not signed in")
                            .foregroundColor(authVM.isSignedIn ? .green : themeVM.current.textSecondary)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    HStack {
                        Text("GitHub")
                            .foregroundColor(themeVM.current.textSecondary)
                        Spacer()
                        Text(authVM.githubConnected ? "Connected" : "Not connected")
                            .foregroundColor(authVM.githubConnected ? .green : themeVM.current.textSecondary)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    if authVM.isSignedIn {
                        Button("Sign Out") { authVM.signOut() }
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("AUTHENTICATION").settingsHeader(theme: themeVM.current)
                }
                .listRowBackground(themeVM.current.surface)

                // AI backend
                Section {
                    HStack {
                        Text("Anthropic API Key (optional)")
                            .foregroundColor(themeVM.current.textSecondary)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-…", text: $apiKeyInput)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("sk-ant-…", text: $apiKeyInput)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        Button { showAPIKey.toggle() } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(themeVM.current.accent)
                        }
                    }
                    Button("Save API Key") {
                        KeychainService.shared.save(key: "anthropic_api_key", value: apiKeyInput)
                        chatVM.configure(apiKey: apiKeyInput)
                    }
                    .foregroundColor(themeVM.current.accent)
                } header: {
                    Text("AI BACKEND").settingsHeader(theme: themeVM.current)
                }
                .listRowBackground(themeVM.current.surface)

                // Data sharing
                Section {
                    Toggle("Share usage analytics (Sigma)", isOn: $dataConsent)
                        .tint(themeVM.current.accent)
                        .foregroundColor(themeVM.current.textSecondary)
                    Text("Only execution metadata is shared — buoyancy, tool route, emotion. Never message content.")
                        .font(.system(size: 11))
                        .foregroundColor(themeVM.current.textSecondary)
                } header: {
                    Text("DATA SHARING").settingsHeader(theme: themeVM.current)
                }
                .listRowBackground(themeVM.current.surface)

                // LEATR constants
                Section {
                    ConstantRow(label: "DOC", value: "\(LEATRIdentity.DOC)")
                    ConstantRow(label: "QS formula", value: "(b·b)·(p·a²)/r")
                    ConstantRow(label: "FRP formula", value: "(xa²·√xa)±1")
                    ConstantRow(label: "Arc Edge C", value: "√(d·DOC)²")
                } header: {
                    Text("LEATR CONSTANTS").settingsHeader(theme: themeVM.current)
                }
                .listRowBackground(themeVM.current.surface)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            let saved = KeychainService.shared.load(key: "anthropic_api_key") ?? ""
            if !saved.isEmpty {
                apiKeyInput = saved
                chatVM.configure(apiKey: saved)
            }
        }
    }
}

struct ConstantRow: View {
    let label: String; let value: String
    @EnvironmentObject var themeVM: ThemeViewModel
    var body: some View {
        HStack {
            Text(label).foregroundColor(themeVM.current.textSecondary).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(themeVM.current.accent)
        }
    }
}

extension Text {
    func settingsHeader(theme: AutumnTheme) -> some View {
        self.font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.accent.opacity(0.7))
            .tracking(2)
    }
}

// MARK: — BRPN Scene stub ViewModel placeholder (full version in BRPNSceneView.swift)
// JournalViewModel defined above; BRPNSceneViewModel in BRPNSceneView.swift