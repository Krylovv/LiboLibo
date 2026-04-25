import Foundation
import Observation

/// Источник правды для списка подкастов и их выпусков.
/// На фазе 1.1: подкасты — из бандла (podcasts.json), выпуски — по RSS, всё in-memory.
@MainActor
@Observable
final class PodcastsRepository {
    private(set) var podcasts: [Podcast] = []
    private(set) var allEpisodes: [Episode] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    init() {
        loadBundledPodcasts()
    }

    private func loadBundledPodcasts() {
        guard let url = Bundle.main.url(forResource: "podcasts", withExtension: "json") else {
            loadError = "podcasts.json не найден в бандле"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(BundledPodcasts.self, from: data)
            podcasts = payload.podcasts
        } catch {
            loadError = "не удалось распарсить podcasts.json: \(error.localizedDescription)"
        }
    }

    /// Загружает RSS всех подкастов параллельно и обновляет `allEpisodes`.
    func loadAllEpisodes() async {
        isLoading = true
        defer { isLoading = false }

        let snapshot = podcasts
        let collected = await Self.fetchAll(podcasts: snapshot)
        allEpisodes = collected.sorted { $0.pubDate > $1.pubDate }
    }

    /// Подгружает RSS подкаста: channel description + список выпусков.
    nonisolated static func fetchFeed(for podcast: Podcast) async -> (channel: PodcastChannelInfo, episodes: [Episode])? {
        do {
            let (data, _) = try await URLSession.shared.data(from: podcast.feedUrl)
            return RSSParser.parse(data: data, podcast: podcast)
        } catch {
            return nil
        }
    }

    nonisolated private static func fetchAll(podcasts: [Podcast]) async -> [Episode] {
        await withTaskGroup(of: [Episode].self) { group in
            for podcast in podcasts {
                group.addTask {
                    await fetchEpisodesOnly(podcast: podcast)
                }
            }
            var all: [Episode] = []
            for await items in group {
                all.append(contentsOf: items)
            }
            return all
        }
    }

    nonisolated private static func fetchEpisodesOnly(podcast: Podcast) async -> [Episode] {
        await fetchFeed(for: podcast)?.episodes ?? []
    }
}

private struct BundledPodcasts: Decodable {
    let podcasts: [Podcast]
}
