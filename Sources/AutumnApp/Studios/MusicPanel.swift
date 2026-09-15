import SwiftUI
import UIKit
import MusicKit
import AutumnServices

/// MUSIC — Apple Music playback inside Autumn, via the existing AutumnMusic actor
/// (Sources/AutumnServices/AutumnMusic.swift). Search the catalog, play a song, and
/// control playback without leaving the app. Requires the listener to have an
/// active Apple Music subscription for full-length playback (MusicKit itself
/// handles that — a non-subscriber gets previews only, same as the Music app).
struct MusicPanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel

    @State private var authStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var query: String = ""
    @State private var results: [MusicItem] = []
    @State private var isSearching = false
    @State private var searchError: String? = nil
    @State private var nowPlayingTitle: String? = nil
    @State private var nowPlayingArtist: String? = nil
    @State private var isPlaying = false
    @State private var playError: String? = nil

    var body: some View {
        let chrome = themeVM.chrome
        VStack(alignment: .leading, spacing: 0) {
            switch authStatus {
            case .authorized:
                content(chrome: chrome)
            case .notDetermined:
                requestView(chrome: chrome)
            case .denied, .restricted:
                deniedView(chrome: chrome)
            @unknown default:
                requestView(chrome: chrome)
            }
        }
        .onAppear { authStatus = MusicAuthorization.currentStatus }
    }

    // MARK: — Authorization gate

    private func requestView(chrome: AutumnTheme) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundColor(chrome.accent)
            Text("Play Apple Music inside Autumn")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text("Search the catalog and play songs while you work. Requires an Apple Music subscription for full playback.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("Connect Apple Music") {
                Task {
                    let granted = await AutumnMusic.shared.requestAccess()
                    authStatus = granted ? .authorized : MusicAuthorization.currentStatus
                }
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(chrome.accent)
            .cornerRadius(20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deniedView(chrome: AutumnTheme) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.3))
            Text("Music access is off for Autumn")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(chrome.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Main content

    private func content(chrome: AutumnTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                TextField("Search songs, albums, artists", text: $query)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                if isSearching {
                    ProgressView().tint(chrome.accent).scaleEffect(0.7)
                } else if !query.isEmpty {
                    Button { query = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.black.opacity(0.28))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(chrome.accent.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 14).padding(.top, 12)

            if let searchError {
                Text(searchError)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#ff7864"))
                    .padding(.horizontal, 14)
            }

            if let nowPlayingTitle {
                nowPlayingBar(chrome: chrome, title: nowPlayingTitle, artist: nowPlayingArtist ?? "")
                    .padding(.horizontal, 14).padding(.top, 4)
            }

            if let playError {
                Text(playError)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#ff7864"))
                    .padding(.horizontal, 14)
            }

            if results.isEmpty && !isSearching {
                Spacer()
                Text(query.isEmpty ? "Search Apple Music to get started" : "No results")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(results) { item in
                            Button {
                                Task { await play(item) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: iconName(for: item.type))
                                        .font(.system(size: 13))
                                        .foregroundColor(chrome.accent)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.9))
                                            .lineLimit(1)
                                        Text(item.artist)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.45))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(item.type.uppercased())
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.25))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            }
                        }
                        // Trailing space so the last row clears the ScrollView's own
                        // bottom edge — same fix as Ash Shard's contact list.
                        Color.clear.frame(height: 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func nowPlayingBar(chrome: AutumnTheme, title: String, artist: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundColor(chrome.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundColor(.white).lineLimit(1)
                Text(artist).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            Button {
                Task {
                    if isPlaying {
                        await AutumnMusic.shared.pause()
                        isPlaying = false
                    } else {
                        do {
                            try await AutumnMusic.shared.resume()
                            isPlaying = true
                        } catch {
                            playError = error.localizedDescription
                        }
                    }
                }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(chrome.accent)
            }
        }
        .padding(10)
        .background(chrome.accent.opacity(0.08))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(chrome.accent.opacity(0.25), lineWidth: 1))
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "song": return "music.note"
        case "album": return "square.stack"
        case "artist": return "person.wave.2"
        default: return "music.note"
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        searchError = nil
        do {
            results = try await AutumnMusic.shared.search(query: q)
        } catch {
            searchError = "Search failed: \(error.localizedDescription)"
        }
        isSearching = false
    }

    private func play(_ item: MusicItem) async {
        guard item.type == "song" else { return } // albums/artists: browse only for now
        playError = nil
        do {
            try await AutumnMusic.shared.play(songID: item.id)
            nowPlayingTitle = item.title
            nowPlayingArtist = item.artist
            isPlaying = true
        } catch {
            playError = "Couldn't play — \(error.localizedDescription)"
        }
    }
}
