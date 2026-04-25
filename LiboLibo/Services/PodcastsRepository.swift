import Foundation
import Observation

/// Источник правды для списка подкастов и глобальной ленты выпусков.
///
/// На фазе 2.0 данные приходят с бэкенда «Либо-Либо» (см. `APIClient`).
/// Бандл `podcasts.json` остаётся как фолбэк на первый запуск без сети, чтобы
/// тинт-обложек и каталог подкастов хоть как-то отрисовались до первого ответа API.
@MainActor
@Observable
final class PodcastsRepository {
    private(set) var podcasts: [Podcast] = []
    private(set) var allEpisodes: [Episode] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        loadBundledPodcasts()
        Task { await self.refreshPodcasts() }
    }

    // MARK: - Подкасты

    /// Подгружает каталог подкастов из API. На ошибке ничего не делает —
    /// в `podcasts` остаётся то, что загрузилось из бандла на старте.
    func refreshPodcasts() async {
        do {
            let fetched = try await api.fetchPodcasts()
            if !fetched.isEmpty { podcasts = fetched }
        } catch {
            // Тихо. Бандл уже подсунут.
        }
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

    // MARK: - Глобальная лента эпизодов

    /// Загружает первую страницу глобальной ленты эпизодов (свежие сверху).
    /// На фазе 2.0 — без бесконечной пагинации: 200 свежих эпизодов хватает
    /// для Фида и «Свежее у подписок». Подгрузка по курсору — отдельной задачей.
    func loadAllEpisodes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.fetchFeed(limit: 200)
            allEpisodes = result.episodes
            loadError = nil
        } catch {
            loadError = "Не удалось загрузить выпуски."
        }
    }
}

private struct BundledPodcasts: Decodable {
    let podcasts: [Podcast]
}
