import Foundation

struct Podcast: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let artist: String
    let feedUrl: URL
    let artworkUrl: URL?
    /// Канальное описание. На фазе 2.0 приходит из бэкенда (поле `description`
    /// в `/v1/podcasts`); до подключения API — из бандла.
    let description: String?
    /// Дата самого свежего выпуска. По ней приложение делит подкасты на
    /// «выходят сейчас / недавно / давно не выходят».
    let lastEpisodeDate: Date?
}
