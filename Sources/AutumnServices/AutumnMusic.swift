import Foundation
import MusicKit

/// AutumnMusicKit — Music playback and library access
/// Allows Autumn to play music on user request
@available(iOS 15.0, *)
public actor AutumnMusic {
    public static let shared = AutumnMusic()
    public init() {}

    // MARK: - Authorization
    public func requestAccess() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    // MARK: - Search and Play
    public func search(query: String) async throws -> [MusicItem] {
        var req = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self, Artist.self])
        req.limit = 10
        let response = try await req.response()
        var items: [MusicItem] = []
        items += response.songs.map    { MusicItem(id: $0.id.rawValue, title: $0.title,    artist: $0.artistName, type: "song") }
        items += response.albums.map   { MusicItem(id: $0.id.rawValue, title: $0.title,    artist: $0.artistName, type: "album") }
        items += response.artists.map  { MusicItem(id: $0.id.rawValue, title: $0.name,     artist: $0.name,       type: "artist") }
        return items
    }

    // TF140: was single-song only (queue = [song]), so there was nothing for
    // skip next/previous to move through — every play() call replaced the
    // whole queue with just one item. Now takes the full result list and the
    // tapped song's index, queuing everything from that point on so
    // ApplicationMusicPlayer's own skipToNextEntry/skipToPreviousEntry have
    // real songs to move between, the same way queuing works in the real
    // Music app.
    private var lastQueueSongIDs: [String] = []

    public func play(songID: String, queueContext: [MusicItem] = []) async throws {
        let songQueue = queueContext.filter { $0.type == "song" }
        if songQueue.isEmpty {
            let musicItemID = MusicItemID(songID)
            var req         = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: musicItemID)
            req.limit       = 1
            let response    = try await req.response()
            guard let song  = response.items.first else { return }
            ApplicationMusicPlayer.shared.queue = [song]
            lastQueueSongIDs = [songID]
        } else {
            let ids = songQueue.map { MusicItemID($0.id) }
            var req = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids)
            let response = try await req.response()
            // Preserve the search-result order, not whatever order the
            // catalog request happens to return them in.
            let byID = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id.rawValue, $0) })
            let ordered = songQueue.compactMap { byID[$0.id] }
            guard !ordered.isEmpty else { return }
            let startIndex = ordered.firstIndex(where: { $0.id.rawValue == songID }) ?? 0
            ApplicationMusicPlayer.shared.queue = ApplicationMusicPlayer.Queue(for: ordered, startingAt: ordered[startIndex])
            lastQueueSongIDs = ordered.map { $0.id.rawValue }
        }
        try await ApplicationMusicPlayer.shared.play()
    }

    public func pause()  { ApplicationMusicPlayer.shared.pause() }
    public func resume() async throws { try await ApplicationMusicPlayer.shared.play() }

    /// Real skip — only meaningful when play() was given a multi-song queue.
    /// Silently does nothing at the natural start/end of the queue rather
    /// than throwing, since a disabled/no-op skip button reads more clearly
    /// than a surfaced error for something this minor.
    public func skipToNext() async {
        try? await ApplicationMusicPlayer.shared.skipToNextEntry()
    }
    public func skipToPrevious() async {
        try? await ApplicationMusicPlayer.shared.skipToPreviousEntry()
    }
    public var hasQueueContext: Bool { lastQueueSongIDs.count > 1 }
}

public struct MusicItem: Sendable, Identifiable {
    public let id:     String
    public let title:  String
    public let artist: String
    public let type:   String
}
