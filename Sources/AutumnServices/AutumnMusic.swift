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

    public func play(songID: String) async throws {
        let musicItemID = MusicItemID(songID)
        var req         = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: musicItemID)
        req.limit       = 1
        let response    = try await req.response()
        guard let song  = response.items.first else { return }
        ApplicationMusicPlayer.shared.queue = [song]
        try await ApplicationMusicPlayer.shared.play()
    }

    public func pause()  { ApplicationMusicPlayer.shared.pause() }
    public func resume() async throws { try await ApplicationMusicPlayer.shared.play() }
}

public struct MusicItem: Sendable, Identifiable {
    public let id:     String
    public let title:  String
    public let artist: String
    public let type:   String
}
