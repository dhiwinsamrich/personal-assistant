#if !APPSTORE
import Foundation
import Combine

// MARK: - Spotify Lyrics

/// Synced lyrics for the Spotify track, from LRCLIB (lrclib.net: free, no account, no key).
/// Off until the user turns it on in Settings → Integrations. One lookup per track change,
/// nothing on a timer: the card picks the current line from the playback position.
@MainActor
final class SpotifyLyrics: ObservableObject {
    static let shared = SpotifyLyrics()
    nonisolated static let enabledKey = "spotifyLyricsEnabled"

    @Published private(set) var lyrics: SyncedLyrics?

    /// Track id → lyrics, or nil when LRCLIB has none (so it isn't asked again).
    private var cache: [String: SyncedLyrics?] = [:]
    private var cacheOrder: [String] = []
    private var loadingId: String?
    private var cancellables = Set<AnyCancellable>()

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    private init() {
        // Fires with the current track on subscribe, then on each change (not on artwork updates)
        SpotifyController.shared.$track
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] track in self?.load(for: track) }
            .store(in: &cancellables)
    }

    /// The Settings toggle changed.
    func settingsChanged() {
        load(for: SpotifyController.shared.track)
    }

    private func load(for track: SpotifyTrack?) {
        lyrics = nil
        guard isEnabled, let track, !track.isAd, !track.title.isEmpty, !track.artist.isEmpty,
              track.id.hasPrefix("spotify:track:") || track.id.hasPrefix("spotify:local:") else { return }
        if let cached = cache[track.id] { lyrics = cached; return }
        guard loadingId != track.id else { return }
        loadingId = track.id
        let id = track.id
        Task {
            defer { if loadingId == id { loadingId = nil } }
            let result = await Self.lookup(title: track.title, artist: track.artist,
                                           album: track.album, duration: track.duration)
            let found: SyncedLyrics?
            switch result {
            case .found(let l): found = l
            case .notFound:     found = nil
            case .failed:       return   // offline or LRCLIB down: try again next time this track plays
            }
            store(found, for: id)
            if isEnabled, SpotifyController.shared.track?.id == id { lyrics = found }
        }
    }

    private func store(_ lyrics: SyncedLyrics?, for id: String) {
        cache.updateValue(lyrics, forKey: id)
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
        while cacheOrder.count > 30 {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    // MARK: - LRCLIB

    private enum Lookup: Sendable { case found(SyncedLyrics), notFound, failed }

    /// Exact match first (title, artist, album, length), then a search that accepts a length within 3 s.
    nonisolated private static func lookup(title: String, artist: String, album: String, duration: Double) async -> Lookup {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [URLQueryItem(name: "track_name", value: title),
                     URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        get.queryItems = items
        guard let (status, data) = await fetch(get.url!) else { return .failed }
        if status == 200, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let lyrics = synced(object) { return .found(lyrics) }
            if object["instrumental"] as? Bool == true { return .notFound }
        } else if status != 404 {
            return .failed
        }

        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: title),
                             URLQueryItem(name: "artist_name", value: artist)]
        guard let (status, data) = await fetch(search.url!) else { return .failed }
        guard status == 200, let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return status == 404 ? .notFound : .failed }
        for object in results {
            let length = (object["duration"] as? NSNumber)?.doubleValue ?? 0
            guard duration <= 0 || length <= 0 || abs(length - duration) <= 3 else { continue }
            if let lyrics = synced(object) { return .found(lyrics) }
        }
        return .notFound
    }

    nonisolated private static func synced(_ object: [String: Any]) -> SyncedLyrics? {
        (object["syncedLyrics"] as? String).flatMap(SyncedLyrics.init(lrc:))
    }

    /// LRCLIB asks clients to name themselves in the User-Agent.
    nonisolated private static func fetch(_ url: URL) async -> (Int, Data)? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        request.setValue("Coucou/\(version) (https://github.com/dhiwinsamrich/personal-assistant)",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }
}
#endif
